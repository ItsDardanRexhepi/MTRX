// ReplayKitManager.swift
// MTRX — Media
//
// Screen recording / clipping for the games (and any app screen) via ReplayKit's
// standard RPScreenRecorder. Records the screen + app audio (microphone OFF by
// default for privacy), writes the clip to a real file, then offers a styled
// preview + Share. Every state is honest: when recording is unavailable
// (Simulator, Screen Time restriction) or the user declines the system consent,
// the UI says so — it never fakes a recording.
//
// Scope is recording/clipping. Live BROADCAST (RPBroadcast*) is intentionally
// not built here — it requires a separate Broadcast Upload Extension target and
// an extension UI; see the note at the bottom of this file.

import SwiftUI
import Observation
import AVKit
import Photos
#if canImport(UIKit)
import UIKit
#endif
#if canImport(ReplayKit)
import ReplayKit
#endif

// MARK: - Manager

@MainActor
@Observable
final class ReplayKitManager {
    static let shared = ReplayKitManager()
    private init() {
        // Reap any clip orphaned by a previous abnormal exit (force-quit/crash
        // while the preview was open).
        sweepStaleClips()
    }

    enum RecordState: Equatable { case idle, starting, recording, processing, unavailable }

    private(set) var state: RecordState = .idle
    private(set) var elapsed: TimeInterval = 0
    /// The most recently saved clip, awaiting preview/share. Cleared on discard.
    private(set) var lastClipURL: URL?
    /// True when the most recent clip was written to the camera roll (Photos).
    private(set) var savedToPhotos = false
    /// Honest one-liner about the camera-roll save, shown inside the clip preview
    /// (not as an alert, so it never collides with the preview sheet). nil = none.
    private(set) var photosMessage: String?
    /// Honest, user-facing message for a real failure/unavailability. nil = none.
    var notice: String?

    var isRecording: Bool { state == .recording }

#if canImport(ReplayKit)
    private let recorder = RPScreenRecorder.shared()
    private var startedAt: Date?
    private var ticker: Timer?

    /// ReplayKit reports availability per-device/per-moment (false on the
    /// Simulator, and when Screen Time restricts recording).
    var isAvailable: Bool { recorder.isAvailable }

    /// Toggle entry point for the UI. Returns true if a clip is ready to preview.
    @discardableResult
    func toggle() async -> Bool {
        switch state {
        case .idle, .unavailable:
            await start()
            return false
        case .recording:
            return await stopAndSave()
        case .starting, .processing:
            return false
        }
    }

    func start() async {
        guard recorder.isAvailable else {
            state = .unavailable
            notice = "Screen recording isn’t available right now. It’s turned off in the Simulator and can be restricted by Screen Time."
            return
        }
        // A new recording supersedes any un-previewed clip; reap stale temp files.
        lastClipURL = nil
        savedToPhotos = false
        photosMessage = nil
        sweepStaleClips()
        // Privacy: capture the screen + app audio only — no microphone.
        recorder.isMicrophoneEnabled = false
        state = .starting
        notice = nil
        do {
            try await recorder.startRecording()
            startedAt = Date()
            elapsed = 0
            state = .recording
            startTicker()
            MtrxHaptics.impact(.medium)
        } catch {
            state = .idle
            notice = "Couldn’t start recording: \(error.localizedDescription)"
        }
    }

    /// Stops recording and writes the clip to a file. Returns true on success.
    @discardableResult
    func stopAndSave() async -> Bool {
        guard state == .recording else { return false }
        state = .processing
        stopTicker()
        let url = Self.makeClipURL()
        do {
            try await recorder.stopRecording(withOutput: url)
            lastClipURL = url
            elapsed = 0
            state = .idle
            MtrxHaptics.success()
            // Save the finished clip straight to the user's camera roll (Photos).
            await saveToPhotos(url)
            return true
        } catch {
            // A failed stop can leave a partial movie behind — clean it up.
            try? FileManager.default.removeItem(at: url)
            elapsed = 0
            state = .idle
            notice = "Couldn’t save the clip: \(error.localizedDescription)"
            return false
        }
    }

    /// Save the finished clip to the user's Photos (camera roll). Add-only access —
    /// MTRX only ever writes the clip, never reads the library. Honest: a real
    /// permission denial or save error is reflected in `photosMessage` (shown in the
    /// preview), and success sets `savedToPhotos`.
    private func saveToPhotos(_ url: URL) async {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { cont.resume(returning: $0) }
        }
        guard status == .authorized || status == .limited else {
            savedToPhotos = false
            photosMessage = "Not added to your camera roll — Photos access is off. Turn it on in Settings ▸ Privacy ▸ Photos to save clips automatically."
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            savedToPhotos = true
            photosMessage = nil
        } catch {
            savedToPhotos = false
            photosMessage = "Couldn’t save to your camera roll: \(error.localizedDescription)"
        }
    }

    /// Stop and discard an in-flight recording — e.g. the user left the game
    /// screen mid-recording — so the recorder, timer, and OS indicator don't
    /// outlive the screen. No preview is shown.
    func cancelIfRecording() async {
        guard state == .recording else { return }
        state = .processing
        stopTicker()
        let url = Self.makeClipURL()
        _ = try? await recorder.stopRecording(withOutput: url)
        try? FileManager.default.removeItem(at: url)
        elapsed = 0
        state = .idle
    }

    /// Clear the reference to the pending clip when the preview is dismissed. The
    /// file is left on disk so an in-flight Share can finish reading it; it's
    /// reaped later by sweepStaleClips(). Deleting it here would race a Share copy.
    func clearPendingClip() {
        lastClipURL = nil
    }

    /// Remove stale MTRX clip files from the temp directory (older than the
    /// window, so a clip a Share is still copying is preserved).
    func sweepStaleClips(olderThan seconds: TimeInterval = 300) {
        let tmp = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-seconds)
        for f in files where f.lastPathComponent.hasPrefix("MTRX-Clip-") {
            let mod = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let mod, mod < cutoff { try? FileManager.default.removeItem(at: f) }
        }
    }

    // MARK: Ticker (drives the on-screen recording timer)

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let started = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(started)
            }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        startedAt = nil
    }

    private static func makeClipURL() -> URL {
        let name = "MTRX-Clip-\(Int(Date().timeIntervalSince1970)).mov"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }
#else
    // ReplayKit unavailable at compile time — keep the app honest & buildable.
    var isAvailable: Bool { false }
    @discardableResult
    func toggle() async -> Bool {
        state = .unavailable
        notice = "Screen recording isn’t available on this build."
        return false
    }
    func cancelIfRecording() async {}
    func clearPendingClip() { lastClipURL = nil }
    func sweepStaleClips(olderThan seconds: TimeInterval = 300) {}
#endif

    static func timeString(_ t: TimeInterval) -> String {
        let s = Int(max(0, t).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Record / clip control (sits in each game's header chrome)

/// A 38×38 record button styled to match the games' close/reset header buttons.
/// Tap to start; tap again to stop and open the clip preview. While recording it
/// shows a red square + a pulsing ring; honest about unavailability via an alert.
struct GameRecordControl: View {
    @State private var rk = ReplayKitManager.shared
    @State private var showPreview = false
    @State private var pulse = false

    var body: some View {
        Button {
            MtrxHaptics.impact(.light)
            Task {
                let ready = await rk.toggle()
                if ready { showPreview = true }
            }
        } label: {
            ZStack {
                if rk.isRecording {
                    Circle().strokeBorder(Color.statusError.opacity(pulse ? 0.15 : 0.7), lineWidth: 2)
                }
                recordGlyph
            }
            .frame(width: 38, height: 38)
            .mtrxLiquidGlass(cornerRadius: 19)
        }
        .buttonStyle(.plain)
        .disabled(rk.state == .starting || rk.state == .processing)
        .accessibilityLabel(rk.isRecording ? "Stop recording" : "Record clip")
        .accessibilityHint(rk.isRecording ? "Stops and opens the clip preview" : "Records the screen")
        .onChange(of: rk.isRecording) { _, recording in
            pulse = false
            if recording {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
            }
        }
        // Leaving the game screen mid-recording stops it (no orphaned recorder).
        .onDisappear { Task { await rk.cancelIfRecording() } }
        .sheet(isPresented: $showPreview, onDismiss: { rk.clearPendingClip() }) {
            ClipPreviewView()
        }
        .alert("Screen recording",
               isPresented: Binding(get: { rk.notice != nil }, set: { if !$0 { rk.notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rk.notice ?? "")
        }
    }

    @ViewBuilder
    private var recordGlyph: some View {
        switch rk.state {
        case .starting, .processing:
            ProgressView().tint(.white)
        case .recording:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.statusError)
                .frame(width: 13, height: 13)
        default:
            Image(systemName: "record.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.statusError)
        }
    }
}

// MARK: - Clip preview + share (styled to match)

/// Styled preview of the just-recorded clip with Share (UIActivityViewController,
/// the same path the rest of the app uses) and Done (discard).
struct ClipPreviewView: View {
    @State private var rk = ReplayKitManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                MtrxGradientBackground(style: .primary).ignoresSafeArea()
                VStack(spacing: Spacing.lg) {
                    if let url = rk.lastClipURL {
                        VideoPlayer(player: player)
                            .clipShape(RoundedRectangle(cornerRadius: Spacing.CornerRadius.lg, style: .continuous))
                            .frame(maxWidth: .infinity)
                            .frame(height: 360)
                            .onAppear {
                                if player == nil {
                                    let p = AVPlayer(url: url)
                                    player = p
                                    p.play()
                                }
                            }

                        VStack(spacing: Spacing.sm) {
                            if rk.savedToPhotos {
                                Label("Saved to your camera roll", systemImage: "checkmark.circle.fill")
                                    .font(.mtrxCaption1).foregroundStyle(Color.labelSecondary)
                            } else if let msg = rk.photosMessage {
                                Text(msg)
                                    .font(.mtrxCaption2).foregroundStyle(Color.labelTertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, Spacing.md)
                            }
                            Button {
                                player?.pause()
                                ClipSharing.present(url: url)
                            } label: {
                                Label("Share clip", systemImage: Symbols.share)
                            }
                            .buttonStyle(MtrxButtonStyle(variant: .primary, size: .regular, fullWidth: true))

                            Button {
                                dismiss()
                            } label: { Text("Done") }
                                .buttonStyle(MtrxButtonStyle(variant: .secondary, size: .regular, fullWidth: true))
                        }
                        .padding(.horizontal, Spacing.lg)
                    } else {
                        Text("No clip available.")
                            .font(.mtrxCallout).foregroundStyle(Color.labelTertiary)
                    }
                }
                .padding(.vertical, Spacing.lg)
            }
            .navigationTitle("Your clip")
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
        .onDisappear {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
            player = nil
        }
    }
}

// MARK: - Share helper (reuses the app's UIActivityViewController pattern)

enum ClipSharing {
    @MainActor
    static func present(url: URL) {
#if canImport(UIKit)
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        activity.popoverPresentationController?.sourceView = top.view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(activity, animated: true)
#endif
    }
}

// MARK: - Live streaming (RPBroadcast) — intentionally NOT built here
//
// Going live (RPBroadcastActivityViewController / RPBroadcastController) needs a
// separate **Broadcast Upload Extension** target (+ optional Broadcast Setup UI
// extension), its own App Group for sample-buffer handoff, and a streaming
// partner/endpoint to receive the RTMP/HLS feed. That's a target + entitlement +
// backend effort, so it's deliberately out of scope here rather than half-built.
