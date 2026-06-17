// MusicKitManager.swift
// MTRX — Apple Music (MusicKit) integration
//
// Real MusicKit: a SEPARATE "Connect Apple Music" authorization step (NOT tied
// to Sign in with Apple), subscription detection, and playback. Every outcome
// is handled honestly:
//   • notDetermined           → not connected, show Connect CTA
//   • denied / restricted     → graceful "not connected" state
//   • authorized + subscriber → full catalog playback (ApplicationMusicPlayer)
//   • authorized, no sub      → 30-second previews + a clear note
//
// No fake "now playing" and no placeholder tracks: `nowPlaying*` is set only
// from a track we actually started, and `chart` is populated only from a real
// MusicKit catalog response (empty otherwise — never invented).
//
// Playback/catalog also require the App ID to have the MusicKit capability
// enabled in the Apple Developer portal; without it the catalog/auth calls
// fail and we fall back to the honest "not connected / unavailable" states.

import Foundation
import SwiftUI
import Observation
#if canImport(MusicKit)
import MusicKit
#endif
import AVFoundation

@MainActor
@Observable
final class MusicKitManager {

    static let shared = MusicKitManager()

    /// Honest, UI-facing connection state.
    enum ConnectionState: Equatable {
        case notConnected        // not yet asked
        case denied              // user declined / restricted
        case connectedFull       // authorized + active subscription
        case connectedPreview    // authorized, no subscription → 30s previews
        case unavailable         // MusicKit not available on this build/device
    }

    private(set) var state: ConnectionState = .notConnected
    private(set) var isWorking = false

    // Real now-playing — set only from a track we actually started.
    private(set) var nowPlayingTitle: String?
    private(set) var nowPlayingArtist: String?
    private(set) var isPlaying = false
    private(set) var isPreviewPlayback = false

    private var previewPlayer: AVPlayer?

    var isConnected: Bool { state == .connectedFull || state == .connectedPreview }

    private init() {
        refreshState()
    }

#if canImport(MusicKit)

    // Real catalog content (top songs) — populated only from a live response.
    private(set) var chart: MusicItemCollection<Song> = []
    private(set) var currentSong: Song?

    /// Distinguishes "still loading" from "load failed" so the UI never shows a
    /// perpetual spinner when MusicKit can't actually reach the catalog (e.g.
    /// the App ID's MusicKit capability isn't enabled yet).
    enum ChartLoad: Equatable { case idle, loading, loaded, failed }
    private(set) var chartLoad: ChartLoad = .idle

    /// Reflect the current authorization without prompting.
    func refreshState() {
        switch MusicAuthorization.currentStatus {
        case .authorized:    break // resolved by updateSubscription()
        case .denied, .restricted: state = .denied
        case .notDetermined: state = .notConnected
        @unknown default:    state = .unavailable
        }
        if MusicAuthorization.currentStatus == .authorized {
            Task { await updateSubscription(); await loadChart() }
        }
    }

    /// The "Connect Apple Music" step — its own MusicKit prompt.
    func connect() async {
        isWorking = true
        defer { isWorking = false }
        let status = await MusicAuthorization.request()
        switch status {
        case .authorized:
            await updateSubscription()
            await loadChart()
        case .denied, .restricted:
            state = .denied
        case .notDetermined:
            state = .notConnected
        @unknown default:
            state = .unavailable
        }
    }

    private func updateSubscription() async {
        do {
            let sub = try await MusicSubscription.current
            state = sub.canPlayCatalogContent ? .connectedFull : .connectedPreview
        } catch {
            // Authorized but subscription couldn't be read — only previews are safe.
            state = .connectedPreview
        }
    }

    private func loadChart() async {
        chartLoad = .loading
        do {
            var request = MusicCatalogChartsRequest(kinds: [.mostPlayed], types: [Song.self])
            request.limit = 15
            let response = try await request.response()
            chart = response.songCharts.first?.items ?? []
            chartLoad = .loaded
        } catch {
            chart = []   // honest empty — never fabricate tracks
            chartLoad = .failed
        }
    }

    /// Play a real catalog song: full track for subscribers, 30s preview otherwise.
    func play(_ song: Song) async {
        currentSong = song
        if state == .connectedFull {
            do {
                let player = ApplicationMusicPlayer.shared
                player.queue = ApplicationMusicPlayer.Queue(for: [song])
                try await player.play()
                setNowPlaying(song, preview: false)
            } catch {
                // Fall back to a preview if full playback fails.
                await playPreview(song)
            }
        } else {
            await playPreview(song)
        }
    }

    private func playPreview(_ song: Song) async {
        guard let url = song.previewAssets?.first?.url else {
            isPlaying = false
            return
        }
        configureAudioSession()
        let player = AVPlayer(url: url)
        previewPlayer = player
        player.play()
        setNowPlaying(song, preview: true)
    }

    func togglePlayPause() {
        if isPreviewPlayback {
            guard let p = previewPlayer else { return }
            if isPlaying { p.pause() } else { p.play() }
            isPlaying.toggle()
        } else {
            let player = ApplicationMusicPlayer.shared
            Task {
                if isPlaying { player.pause(); isPlaying = false }
                else { try? await player.play(); isPlaying = true }
            }
        }
    }

    func stop() {
        previewPlayer?.pause()
        previewPlayer = nil
        if !isPreviewPlayback { ApplicationMusicPlayer.shared.stop() }
        isPlaying = false
        nowPlayingTitle = nil
        nowPlayingArtist = nil
    }

    private func setNowPlaying(_ song: Song, preview: Bool) {
        nowPlayingTitle = song.title
        nowPlayingArtist = song.artistName
        isPreviewPlayback = preview
        isPlaying = true
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

#else
    // MusicKit unavailable at compile time — keep the app honest & buildable.
    func refreshState() { state = .unavailable }
    func connect() async { state = .unavailable }
    func togglePlayPause() {}
    func stop() {}
#endif
}
