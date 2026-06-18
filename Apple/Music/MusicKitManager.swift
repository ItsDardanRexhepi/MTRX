// MusicKitManager.swift
// MTRX — Apple Music (MusicKit) integration
//
// Real MusicKit: a SEPARATE "Connect Apple Music" authorization step (NOT tied
// to Sign in with Apple), subscription detection, and full playback transport
// (queue, scrubbing/seek, next/previous, repeat off/all/one, shuffle). Every
// outcome is handled honestly:
//   • notDetermined           → not connected, show Connect CTA
//   • denied / restricted     → graceful "not connected" state
//   • authorized + subscriber → full catalog playback (ApplicationMusicPlayer)
//   • authorized, no sub      → 30-second previews + a clear note
//
// No fake "now playing" and no placeholder tracks: now-playing is set only from
// a track we actually started, and content comes only from real MusicKit
// responses. Playback also requires the App ID's MusicKit capability; without
// it the calls fail and we fall back to the honest unavailable/preview states.

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
        case notConnected, denied, connectedFull, connectedPreview, unavailable
    }

    /// Repeat behaviour, matching Apple Music: off, repeat-all (queue), repeat-one (song).
    enum RepeatMode: Equatable { case off, all, one }

    /// Result of a Trinity "play X" request.
    struct PlayOutcome { let ok: Bool; let message: String }

    private(set) var state: ConnectionState = .notConnected
    private(set) var isWorking = false

    // Now playing — set only from a track we actually started.
    private(set) var nowPlayingTitle: String?
    private(set) var nowPlayingArtist: String?
    private(set) var isPlaying = false
    private(set) var isPreviewPlayback = false

    // Transport state.
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var repeatMode: RepeatMode = .off
    var shuffleOn: Bool = false

    var isConnected: Bool { state == .connectedFull || state == .connectedPreview }
    var hasNowPlaying: Bool { nowPlayingTitle != nil }

    private var previewPlayer: AVPlayer?
    private var ticker: Timer?
    private var endObserver: NSObjectProtocol?

    private init() {
        refreshState()
    }

#if canImport(MusicKit)

    // Real catalog content (top songs) — populated only from a live response.
    private(set) var chart: MusicItemCollection<Song> = []
    enum ChartLoad: Equatable { case idle, loading, loaded, failed }
    private(set) var chartLoad: ChartLoad = .idle

    private(set) var currentSong: Song?
    private(set) var queueSongs: [Song] = []
    private(set) var currentIndex: Int = 0

    /// The real artwork of the current track (for the player + Home widget).
    var nowPlayingArtwork: Artwork? { currentSong?.artwork }

    // MARK: - Authorization / subscription

    func refreshState() {
        switch MusicAuthorization.currentStatus {
        case .authorized:    break
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
        switch await MusicAuthorization.request() {
        case .authorized:          await updateSubscription(); await loadChart()
        case .denied, .restricted: state = .denied
        case .notDetermined:       state = .notConnected
        @unknown default:          state = .unavailable
        }
    }

    private func updateSubscription() async {
        do {
            let sub = try await MusicSubscription.current
            state = sub.canPlayCatalogContent ? .connectedFull : .connectedPreview
        } catch {
            state = .connectedPreview
        }
    }

    private func loadChart() async {
        chartLoad = .loading
        do {
            var request = MusicCatalogChartsRequest(kinds: [.mostPlayed], types: [Song.self])
            request.limit = 25
            let response = try await request.response()
            chart = response.songCharts.first?.items ?? []
            chartLoad = .loaded
        } catch {
            chart = []
            chartLoad = .failed
        }
    }

    // MARK: - Start playback

    /// Play a song from the chart, using the whole chart as the queue.
    func play(_ song: Song) async {
        let songs = Array(chart)
        let idx = songs.firstIndex(where: { $0.id == song.id }) ?? 0
        await startQueue(songs: songs.isEmpty ? [song] : songs, at: idx)
    }

    /// Trinity entry point: search the catalog and play the best match.
    func play(query: String) async -> PlayOutcome {
        guard isConnected else {
            return PlayOutcome(ok: false, message: "Connect Apple Music in the player first, then I can play that for you.")
        }
        do {
            var req = MusicCatalogSearchRequest(term: query, types: [Song.self])
            req.limit = 15
            let resp = try await req.response()
            let songs = Array(resp.songs)
            guard let first = songs.first else {
                return PlayOutcome(ok: false, message: "I couldn't find \u{201C}\(query)\u{201D} on Apple Music.")
            }
            await startQueue(songs: songs, at: 0)
            let preview = state == .connectedPreview ? " (30-second preview \u{2014} subscribe to Apple Music for the full song)" : ""
            return PlayOutcome(ok: true, message: "Now playing \(first.title) by \(first.artistName)\(preview).")
        } catch {
            return PlayOutcome(ok: false, message: "I couldn't reach Apple Music just now.")
        }
    }

    /// Jump to a specific track in the current queue (from the Up Next list).
    func jump(to index: Int) {
        guard queueSongs.indices.contains(index) else { return }
        Task { await startQueue(songs: queueSongs, at: index) }
    }

    private func startQueue(songs: [Song], at index: Int) async {
        guard !songs.isEmpty else { return }
        queueSongs = songs
        currentIndex = max(0, min(index, songs.count - 1))
        let song = songs[currentIndex]
        currentSong = song
        if state == .connectedFull {
            await startAppPlayback(at: song, in: songs)
        } else {
            await startPreviewPlayback(at: currentIndex)
        }
        startTicker()
    }

    private func startAppPlayback(at song: Song, in songs: [Song]) async {
        let p = ApplicationMusicPlayer.shared
        p.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: song)
        applyModes()
        do {
            try await p.play()
            isPreviewPlayback = false
            setNowPlaying(song, preview: false)
            duration = song.duration ?? 0
        } catch {
            await startPreviewPlayback(at: currentIndex)
        }
    }

    private func startPreviewPlayback(at index: Int) async {
        guard queueSongs.indices.contains(index) else { return }
        currentIndex = index
        let song = queueSongs[index]
        currentSong = song
        guard let url = song.previewAssets?.first?.url else { isPlaying = false; return }
        configureAudioSession()
        removeEndObserver()
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        previewPlayer = p
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.previewEnded() }
        }
        p.play()
        isPreviewPlayback = true
        setNowPlaying(song, preview: true)
        duration = song.duration.map { min($0, 30) } ?? 30
    }

    private func previewEnded() {
        switch repeatMode {
        case .one: previewPlayer?.seek(to: .zero); previewPlayer?.play()
        case .all, .off: skipNext()
        }
    }

    // MARK: - Transport

    func togglePlayPause() {
        if isPreviewPlayback {
            guard let p = previewPlayer else { return }
            if isPlaying { p.pause() } else { p.play() }
            isPlaying.toggle()
        } else {
            let p = ApplicationMusicPlayer.shared
            Task {
                if isPlaying { p.pause(); isPlaying = false }
                else { try? await p.play(); isPlaying = true }
            }
        }
    }

    func skipNext() {
        if state == .connectedFull && !isPreviewPlayback {
            Task { try? await ApplicationMusicPlayer.shared.skipToNextEntry(); currentTime = 0; syncFromAppPlayer() }
            return
        }
        guard !queueSongs.isEmpty else { return }
        if let n = nextIndex() { Task { await startPreviewPlayback(at: n) } } else { stop() }
    }

    func skipPrevious() {
        if currentTime > 3 { seek(to: 0); return }
        if state == .connectedFull && !isPreviewPlayback {
            Task { try? await ApplicationMusicPlayer.shared.skipToPreviousEntry(); currentTime = 0; syncFromAppPlayer() }
            return
        }
        guard !queueSongs.isEmpty else { return }
        let prev = (currentIndex - 1 + queueSongs.count) % queueSongs.count
        Task { await startPreviewPlayback(at: prev) }
    }

    private func nextIndex() -> Int? {
        guard !queueSongs.isEmpty else { return nil }
        if shuffleOn && queueSongs.count > 1 {
            var r = currentIndex
            while r == currentIndex { r = Int.random(in: 0..<queueSongs.count) }
            return r
        }
        if currentIndex + 1 < queueSongs.count { return currentIndex + 1 }
        return repeatMode == .off ? nil : 0
    }

    func seek(to time: TimeInterval) {
        currentTime = time
        if isPreviewPlayback {
            previewPlayer?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        } else {
            ApplicationMusicPlayer.shared.playbackTime = time
        }
    }

    func cycleRepeat() {
        repeatMode = repeatMode == .off ? .all : (repeatMode == .all ? .one : .off)
        applyModes()
    }

    func toggleShuffle() {
        shuffleOn.toggle()
        applyModes()
    }

    private func applyModes() {
        guard state == .connectedFull, !isPreviewPlayback else { return }
        let p = ApplicationMusicPlayer.shared
        switch repeatMode {
        case .off: p.state.repeatMode = MusicPlayer.RepeatMode.none
        case .all: p.state.repeatMode = MusicPlayer.RepeatMode.all
        case .one: p.state.repeatMode = MusicPlayer.RepeatMode.one
        }
        p.state.shuffleMode = shuffleOn ? MusicPlayer.ShuffleMode.songs : MusicPlayer.ShuffleMode.off
    }

    func stop() {
        previewPlayer?.pause(); previewPlayer = nil
        removeEndObserver()
        if state == .connectedFull && !isPreviewPlayback { ApplicationMusicPlayer.shared.stop() }
        stopTicker()
        isPlaying = false
        nowPlayingTitle = nil; nowPlayingArtist = nil
        currentTime = 0; duration = 0
        currentSong = nil
    }

    // MARK: - Sync

    private func setNowPlaying(_ song: Song, preview: Bool) {
        nowPlayingTitle = song.title
        nowPlayingArtist = song.artistName
        isPreviewPlayback = preview
        isPlaying = true
        currentTime = 0
    }

    private func syncFromAppPlayer() {
        let p = ApplicationMusicPlayer.shared
        guard let entry = p.queue.currentEntry else { return }
        nowPlayingTitle = entry.title
        nowPlayingArtist = entry.subtitle
        if let s = queueSongs.first(where: { $0.title == entry.title }) {
            currentSong = s
            if let d = s.duration { duration = d }
            currentIndex = queueSongs.firstIndex(where: { $0.id == s.id }) ?? currentIndex
        }
    }

    private func startTicker() {
        stopTicker()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    private func stopTicker() { ticker?.invalidate(); ticker = nil }

    private func tick() {
        if isPreviewPlayback {
            if let t = previewPlayer?.currentTime().seconds, t.isFinite { currentTime = t }
        } else {
            let p = ApplicationMusicPlayer.shared
            currentTime = p.playbackTime
            isPlaying = (p.state.playbackStatus == .playing)
            syncFromAppPlayer()
        }
    }

    private func removeEndObserver() {
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: - Library (the user's saved Apple Music content)
    //
    // Reads go through MusicLibraryRequest, gated by the SAME authorization this
    // manager owns; playback goes through the SAME queue engine above. No second
    // MusicKit path. Reads need authorization + the App ID's MusicKit capability
    // (no subscription required to READ the library); full playback still needs
    // a subscription (else the preview fallback).

    /// Public play entry for an arbitrary song list (library / playlist / album).
    func playSongs(_ songs: [Song], startAt index: Int = 0) async {
        await startQueue(songs: songs, at: index)
    }

    func libraryPlaylists(limit: Int = 25) async throws -> MusicItemCollection<Playlist> {
        var request = MusicLibraryRequest<Playlist>()
        request.limit = limit
        return try await request.response().items
    }

    func librarySongs(limit: Int = 50, recentlyAdded: Bool = false) async throws -> MusicItemCollection<Song> {
        var request = MusicLibraryRequest<Song>()
        request.limit = limit
        if recentlyAdded { request.sort(by: \.libraryAddedDate, ascending: false) }
        return try await request.response().items
    }

    func libraryAlbums(limit: Int = 50, recentlyAdded: Bool = false) async throws -> MusicItemCollection<Album> {
        var request = MusicLibraryRequest<Album>()
        request.limit = limit
        if recentlyAdded { request.sort(by: \.libraryAddedDate, ascending: false) }
        return try await request.response().items
    }

    func libraryArtists(limit: Int = 50) async throws -> MusicItemCollection<Artist> {
        var request = MusicLibraryRequest<Artist>()
        request.limit = limit
        return try await request.response().items
    }

    /// Next page of any library collection — pagination for large libraries.
    func loadMore<T: MusicItem>(_ collection: MusicItemCollection<T>) async -> MusicItemCollection<T>? {
        guard collection.hasNextBatch else { return nil }
        return try? await collection.nextBatch()
    }

    /// Playable songs of a playlist (music videos skipped) for the shared engine.
    func songs(of playlist: Playlist) async throws -> [Song] {
        let detailed = try await playlist.with([.tracks])
        return Self.songs(from: detailed.tracks)
    }

    func songs(of album: Album) async throws -> [Song] {
        let detailed = try await album.with([.tracks])
        return Self.songs(from: detailed.tracks)
    }

    func albums(of artist: Artist) async throws -> MusicItemCollection<Album> {
        let detailed = try await artist.with([.albums])
        return detailed.albums ?? []
    }

    private static func songs(from tracks: MusicItemCollection<Track>?) -> [Song] {
        guard let tracks else { return [] }
        return tracks.compactMap { track in
            if case .song(let s) = track { return s }
            return nil
        }
    }

    // MARK: - Catalog search (find content to play or add to the library)
    //
    // Real Apple Music catalog search via MusicCatalogSearchRequest, gated by the
    // SAME authorization this manager owns. Search needs authorization + the App
    // ID's MusicKit capability but NOT a subscription (full playback of results
    // still needs one; previews otherwise). Results are never fabricated.

    struct CatalogSearchResults {
        var songs: MusicItemCollection<Song> = []
        var albums: MusicItemCollection<Album> = []
        var artists: MusicItemCollection<Artist> = []
        var playlists: MusicItemCollection<Playlist> = []
        var isEmpty: Bool { songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty }
    }

    func searchCatalog(_ term: String, limit: Int = 20) async throws -> CatalogSearchResults {
        var request = MusicCatalogSearchRequest(
            term: term,
            types: [Song.self, Album.self, Artist.self, Playlist.self]
        )
        request.limit = limit
        let response = try await request.response()
        return CatalogSearchResults(
            songs: response.songs,
            albums: response.albums,
            artists: response.artists,
            playlists: response.playlists
        )
    }

    // MARK: - Add to library (real MusicKit write — operate Apple Music)
    //
    // MusicLibrary.shared.add is a genuine write to the user's Apple Music
    // library; it requires authorization (read+write). We only report "added"
    // when the write actually succeeds, and surface a real failure otherwise —
    // never a fake confirmation.

    enum AddOutcome { case added, failed }

    func addToLibrary(_ song: Song) async -> AddOutcome {
        do { try await MusicLibrary.shared.add(song); return .added }
        catch { return .failed }
    }

    func addToLibrary(album: Album) async -> AddOutcome {
        do { try await MusicLibrary.shared.add(album); return .added }
        catch { return .failed }
    }

    func addToLibrary(playlist: Playlist) async -> AddOutcome {
        do { try await MusicLibrary.shared.add(playlist); return .added }
        catch { return .failed }
    }

#else
    // MusicKit unavailable at compile time — keep the app honest & buildable.
    func refreshState() { state = .unavailable }
    func connect() async { state = .unavailable }
    func play(query: String) async -> PlayOutcome { PlayOutcome(ok: false, message: "Apple Music isn't available on this build.") }
    func togglePlayPause() {}
    func skipNext() {}
    func skipPrevious() {}
    func seek(to time: TimeInterval) {}
    func cycleRepeat() {}
    func toggleShuffle() {}
    func stop() {}
#endif
}
