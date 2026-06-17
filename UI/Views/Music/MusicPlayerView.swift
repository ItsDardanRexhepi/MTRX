// MusicPlayerView.swift
// MTRX — Apple Music player (MusicKit)
//
// MTRX's own player UI over MusicKit — native-feeling but clearly MTRX's, not a
// clone of the Apple Music app. Follows Apple Music Identity Guidelines: Apple
// Music attribution lockup, real catalog artwork via ArtworkImage, the official
// MusicKit subscription-offer sheet. Every state is honest (see MusicKitManager).

import SwiftUI
import Observation
#if canImport(MusicKit)
import MusicKit
#endif

// MARK: - Apple Music attribution lockup (Identity Guidelines)

private struct AppleMusicBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "apple.logo")
                .font(.system(size: 11, weight: .medium))
            Text("Music")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.labelSecondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Apple Music")
    }
}

// MARK: - Home widget card

/// Tappable Home-screen music card (placed below the Portfolio card, above
/// Quick Actions). Shows real now-playing when playing, otherwise an honest
/// connect / open affordance.
struct HomeMusicWidget: View {
    @State private var music = MusicKitManager.shared
    let onOpen: () -> Void

    var body: some View {
        Button {
            MtrxHaptics.impact(.light)
            onOpen()
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.surfaceOverlay)
                        .frame(width: 48, height: 48)
                    Image(systemName: music.isPlaying ? "waveform" : "music.note")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentPrimary)
                        .symbolEffect(.variableColor, isActive: music.isPlaying)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryText)
                        .font(.mtrxHeadline)
                        .foregroundStyle(Color.labelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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

                Spacer()
                AppleMusicBadge()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.labelTertiary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.md)
            .background(Color.surfaceCard, in: RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the Apple Music player")
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

// MARK: - Full player

struct MusicPlayerView: View {
    @State private var music = MusicKitManager.shared
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
                ToolbarItem(placement: .topBarLeading) { AppleMusicBadge() }
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
    }

    @ViewBuilder
    private var content: some View {
        switch music.state {
        case .notConnected: connectState
        case .denied:       deniedState
        case .unavailable:  unavailableState
        case .connectedFull, .connectedPreview: playerState
        }
    }

    // MARK: States

    private var connectState: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentPrimary)
            Text("Connect Apple Music")
                .font(.mtrxTitle2).foregroundStyle(Color.labelPrimary)
            Text("Listen right inside MTRX. This is a separate Apple Music permission — it's not part of signing in.")
                .font(.mtrxBody).foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Spacing.lg)
            Button {
                Task { await music.connect() }
            } label: {
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
            Text("Apple Music isn't connected")
                .font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
            Text("You declined Apple Music access. You can enable it in Settings if you'd like to listen here.")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Spacing.lg)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: { Text("Open Settings") }
                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular))
            Spacer()
        }
    }

    private var unavailableState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle").font(.system(size: 44)).foregroundStyle(Color.labelTertiary)
            Text("Apple Music is unavailable")
                .font(.mtrxHeadline).foregroundStyle(Color.labelPrimary)
            Text("Apple Music can't be reached on this device right now.")
                .font(.mtrxCallout).foregroundStyle(Color.labelSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, Spacing.lg)
            Spacer()
        }
    }

#if canImport(MusicKit)
    private var playerState: some View {
        VStack(spacing: 0) {
            if music.state == .connectedPreview {
                previewNotice
            }
            chartList
            nowPlayingBar
        }
        .musicSubscriptionOffer(isPresented: $showSubscriptionOffer)
    }

    private var previewNotice: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "info.circle")
            Text("You're hearing 30-second previews. Subscribe to Apple Music for full songs.")
                .font(.mtrxCaption1)
            Spacer()
            Button("Subscribe") { showSubscriptionOffer = true }
                .font(.mtrxCaptionBold)
                .foregroundStyle(Color.accentPrimary)
        }
        .foregroundStyle(Color.labelSecondary)
        .padding(Spacing.sm)
        .background(Color.surfaceOverlay)
    }

    private var chartList: some View {
        ScrollView {
            if music.chart.isEmpty {
                Group {
                    switch music.chartLoad {
                    case .loading, .idle:
                        Text("Loading top songs…")
                            .foregroundStyle(Color.labelTertiary)
                    case .failed:
                        Text("Couldn't load Apple Music content. The app's MusicKit capability may not be enabled yet.")
                            .foregroundStyle(Color.labelSecondary)
                            .multilineTextAlignment(.center)
                    case .loaded:
                        Text("No songs available right now.")
                            .foregroundStyle(Color.labelTertiary)
                    }
                }
                .font(.mtrxCallout)
                .frame(maxWidth: .infinity).padding(.horizontal, Spacing.lg).padding(.top, Spacing.xl)
            } else {
                LazyVStack(spacing: Spacing.xs) {
                    ForEach(music.chart) { song in
                        Button {
                            Task { await music.play(song) }
                        } label: {
                            songRow(song)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.md)
            }
        }
    }

    private func songRow(_ song: Song) -> some View {
        HStack(spacing: Spacing.sm) {
            if let artwork = song.artwork {
                ArtworkImage(artwork, width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 6).fill(Color.surfaceOverlay).frame(width: 44, height: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).font(.mtrxCallout).foregroundStyle(Color.labelPrimary).lineLimit(1)
                Text(song.artistName).font(.mtrxCaption1).foregroundStyle(Color.labelSecondary).lineLimit(1)
            }
            Spacer()
            if music.currentSong?.id == song.id, music.isPlaying {
                Image(systemName: "waveform").foregroundStyle(Color.accentPrimary)
            }
        }
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(song.title) by \(song.artistName)")
        .accessibilityHint(music.state == .connectedFull ? "Plays the song" : "Plays a 30-second preview")
    }

    @ViewBuilder
    private var nowPlayingBar: some View {
        if let title = music.nowPlayingTitle {
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.mtrxCaptionBold).foregroundStyle(Color.labelPrimary).lineLimit(1)
                    Text(music.nowPlayingArtist ?? "").font(.mtrxCaption2).foregroundStyle(Color.labelSecondary).lineLimit(1)
                }
                Spacer()
                Button { music.togglePlayPause() } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .accessibilityLabel(music.isPlaying ? "Pause" : "Play")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.labelPrimary)
                }
                Button { music.stop() } label: {
                    Image(systemName: "stop.fill")
                        .accessibilityLabel("Stop")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.labelSecondary)
                }
            }
            .padding(Spacing.md)
            .background(.ultraThinMaterial)
        }
    }
#else
    private var playerState: some View { unavailableState }
#endif
}
