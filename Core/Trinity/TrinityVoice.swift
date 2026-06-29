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
    /// Exact system-voice identifiers to use when installed, in priority order (e.g.
    /// the premium "Ava" voice). This is what gives Trinity HER voice rather than
    /// whatever generic voice happens to be first on the device.
    var preferredVoiceIdentifiers: [String] = []
    /// Voice-name fragments to prefer when no exact identifier is installed.
    var preferredVoiceNames: [String] = []
    /// The voice gender to keep consistent across devices and languages.
    var preferredGender: AVSpeechSynthesisVoiceGender = .unspecified

    /// Trinity's voice: a calm, measured, confident FEMALE voice. Prefers the premium
    /// "Ava" voice; otherwise the best available female voice — never a random first pick.
    static let trinity = VoiceProfile(
        identifier: "com.mtrx.trinity",
        name: "Trinity",
        rate: 0.48,
        pitch: 1.05,
        volume: 0.85,
        language: "en-US",
        preUtteranceDelay: 0.1,
        postUtteranceDelay: 0.2,
        preferredVoiceIdentifiers: [
            "com.apple.voice.premium.en-US.Ava",
            "com.apple.voice.enhanced.en-US.Ava"
        ],
        preferredVoiceNames: ["Ava", "Samantha", "Allison", "Susan", "Nicky", "Zoe"],
        preferredGender: .female
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
        // Do NOT configure/activate the audio session here. Activating the .playback
        // session on init would interrupt the user's Apple Music the moment an agent chat
        // opens — before any voice is used. The session is configured lazily in speak()
        // (and re-asserted there after the mic), so simply opening a chat leaves other
        // audio playing untouched.
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
        // V5 — re-assert the .playback session before speaking. The mic (STT) switches the shared
        // AVAudioSession to .record; this flips it back to .playback so the reply plays on the right
        // route. Idempotent for back-to-back replies; the mic side stops TTS before it records, so
        // the two never fight over the session.
        configureAudioSession()
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

    /// Speak `text` in the given language (a short code like "fr", "ja", "zh-Hans"), choosing the
    /// best on-device voice for it. Used by the multilingual chat TTS so Trinity speaks replies in
    /// the user's language. Keeps Trinity's rate/pitch; only the language/voice changes.
    func speak(_ text: String, languageCode: String) async {
        let base = currentProfile
        let profile = VoiceProfile(
            identifier: base.identifier, name: base.name, rate: base.rate, pitch: base.pitch,
            volume: base.volume, language: Self.ttsLocale(for: languageCode),
            preUtteranceDelay: base.preUtteranceDelay, postUtteranceDelay: base.postUtteranceDelay,
            preferredVoiceIdentifiers: base.preferredVoiceIdentifiers,
            preferredVoiceNames: base.preferredVoiceNames,
            preferredGender: base.preferredGender
        )
        await speak(text, with: profile)
    }

    /// Map a bare language code (NLLanguage raw value) to a representative BCP-47 locale the
    /// speech synthesizer has voices for.
    static func ttsLocale(for code: String) -> String {
        switch code {
        case "en": return "en-US"; case "da": return "da-DK"; case "nl": return "nl-NL"
        case "fr": return "fr-FR"; case "de": return "de-DE"; case "it": return "it-IT"
        case "nb", "no": return "nb-NO"; case "pt": return "pt-BR"; case "es": return "es-ES"
        case "sv": return "sv-SE"; case "tr": return "tr-TR"; case "vi": return "vi-VN"
        case "zh-Hans": return "zh-CN"; case "zh-Hant": return "zh-TW"
        case "ja": return "ja-JP"; case "ko": return "ko-KR"
        default: return code
        }
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
        let all = AVSpeechSynthesisVoice.speechVoices()

        // 1) An exact preferred voice (e.g. premium "Ava"), if it's installed.
        for id in profile.preferredVoiceIdentifiers {
            if let v = all.first(where: { $0.identifier == id }) { return v }
        }

        let langExact = all.filter { $0.language == profile.language }
        let langFamily = all.filter { $0.language.hasPrefix(profile.language.prefix(2)) }

        // 2) The best voice matching the profile's gender + name preferences, ranked by
        //    quality — so Trinity is consistently HER voice, not a random first pick.
        func best(in pool: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
            guard !pool.isEmpty else { return nil }
            let byGender = profile.preferredGender == .unspecified
                ? pool : pool.filter { $0.gender == profile.preferredGender }
            let gendered = byGender.isEmpty ? pool : byGender
            let named = gendered.filter { v in
                profile.preferredVoiceNames.contains { v.name.localizedCaseInsensitiveContains($0) }
            }
            return (named.isEmpty ? gendered : named)
                .max { Self.qualityRank($0.quality) < Self.qualityRank($1.quality) }
        }

        return best(in: langExact) ?? best(in: langFamily) ?? langExact.first ?? all.first
    }

    private static func qualityRank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
        switch q {
        case .premium: return 3
        case .enhanced: return 2
        default: return 1
        }
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
