//
//  TrinityVoice.swift
//  MTRX — Trinity
//
//  AVFoundation voice playback with custom voice parameters for Trinity.
//

import Foundation
import AVFoundation

// MARK: - Voice Profile

/// Defines the characteristics of a voice output profile.
struct VoiceProfile: Sendable {
    let identifier: String
    let name: String
    let rate: Float          // 0.0 - 1.0 (AVSpeechUtteranceDefaultSpeechRate ~0.5)
    let pitch: Float         // 0.5 - 2.0 (1.0 is default)
    let volume: Float        // 0.0 - 1.0
    let language: String
    let preUtteranceDelay: TimeInterval
    let postUtteranceDelay: TimeInterval

    /// Trinity's default voice: calm, measured, confident.
    static let trinity = VoiceProfile(
        identifier: "com.mtrx.trinity",
        name: "Trinity",
        rate: 0.48,
        pitch: 1.05,
        volume: 0.85,
        language: "en-US",
        preUtteranceDelay: 0.1,
        postUtteranceDelay: 0.2
    )
}

// MARK: - Trinity Voice

/// Handles text-to-speech playback for Trinity using AVFoundation.
final class TrinityVoice: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private let synthesizer: AVSpeechSynthesizer
    private var currentProfile: VoiceProfile
    private var isSpeaking: Bool { synthesizer.isSpeaking }
    private var isPaused: Bool { synthesizer.isPaused }

    private var completionHandler: (() -> Void)?
    private var selectedVoice: AVSpeechSynthesisVoice?

    // MARK: - Initialization

    init(profile: VoiceProfile = .trinity) {
        self.synthesizer = AVSpeechSynthesizer()
        self.currentProfile = profile
        super.init()
        self.synthesizer.delegate = self
        self.selectedVoice = selectBestVoice(for: profile)
        configureAudioSession()
    }

    // MARK: - Audio Session

    /// Configure AVAudioSession for smooth Trinity speech playback.
    ///
    /// We use the ``.playback`` category with the ``.voicePrompt``
    /// mode so iOS routes the audio to the current output correctly
    /// whether the user is on speakerphone, Bluetooth, or AirPods, and
    /// we duck other audio sources (music, podcasts) while Trinity is
    /// speaking. ``.allowBluetoothA2DP`` and ``.allowAirPlay`` let the
    /// output follow whatever device the user has connected, and
    /// ``.mixWithOthers`` is intentionally *not* set — we want music to
    /// duck, not mix, so Trinity's voice stays intelligible.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            // Falling back to the most conservative configuration keeps
            // speech working even if the richer options are rejected
            // (e.g. during a CallKit session).
            do {
                try session.setCategory(.playback, mode: .spokenAudio)
                try session.setActive(true)
            } catch {
                print("[TrinityVoice] Audio session configuration failed: \(error)")
            }
        }
    }

    // MARK: - Speech

    /// Speak the given text using Trinity's voice profile.
    /// - Parameter text: The text to speak.
    func speak(_ text: String) async {
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }

        let utterance = buildUtterance(for: text)

        await withCheckedContinuation { continuation in
            completionHandler = {
                continuation.resume()
            }
            synthesizer.speak(utterance)
        }
    }

    /// Speak with a custom voice profile override.
    /// - Parameters:
    ///   - text: The text to speak.
    ///   - profile: The voice profile to use.
    func speak(_ text: String, with profile: VoiceProfile) async {
        let previousProfile = currentProfile
        currentProfile = profile
        selectedVoice = selectBestVoice(for: profile)
        await speak(text)
        currentProfile = previousProfile
        selectedVoice = selectBestVoice(for: currentProfile)
    }

    /// Pause current speech at the next word boundary.
    func pause() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Resume paused speech.
    func resume() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
    }

    /// Stop all speech immediately.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        completionHandler?()
        completionHandler = nil
    }

    // MARK: - Voice Profile Management

    /// Set the active voice profile.
    /// - Parameter profile: The new voice profile to use.
    func setVoiceProfile(_ profile: VoiceProfile) {
        currentProfile = profile
        selectedVoice = selectBestVoice(for: profile)
    }

    /// List available system voices for the current language.
    /// - Returns: Available voice identifiers.
    func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(currentProfile.language.prefix(2).description) }
    }

    // MARK: - Private Helpers

    private func buildUtterance(for text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = currentProfile.rate
        utterance.pitchMultiplier = currentProfile.pitch
        utterance.volume = currentProfile.volume
        utterance.preUtteranceDelay = currentProfile.preUtteranceDelay
        utterance.postUtteranceDelay = currentProfile.postUtteranceDelay

        if let voice = selectedVoice {
            utterance.voice = voice
        }

        return utterance
    }

    private func selectBestVoice(for profile: VoiceProfile) -> AVSpeechSynthesisVoice? {
        // Prefer enhanced/premium voices
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == profile.language }

        // Try to find a premium quality voice first
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return voices.first
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension TrinityVoice: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        completionHandler?()
        completionHandler = nil
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        completionHandler?()
        completionHandler = nil
    }
}
