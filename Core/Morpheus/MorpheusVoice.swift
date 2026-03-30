//
//  MorpheusVoice.swift
//  MTRX — Morpheus
//
//  AVFoundation voice playback with urgent, authoritative tone distinct from Trinity.
//

import Foundation
import AVFoundation

// MARK: - Morpheus Voice Profile

extension VoiceProfile {
    /// Morpheus voice: deeper, more urgent, authoritative.
    /// Distinct from Trinity's calm, measured tone.
    static let morpheus = VoiceProfile(
        identifier: "com.mtrx.morpheus",
        name: "Morpheus",
        rate: 0.42,         // Slightly slower for gravity
        pitch: 0.90,        // Deeper pitch
        volume: 0.95,       // Louder for urgency
        language: "en-US",
        preUtteranceDelay: 0.05,   // Minimal delay — urgency
        postUtteranceDelay: 0.3    // Slight pause after for impact
    )

    /// Morpheus critical alert voice: even more urgent.
    static let morpheusCritical = VoiceProfile(
        identifier: "com.mtrx.morpheus.critical",
        name: "Morpheus Critical",
        rate: 0.50,         // Faster for urgency
        pitch: 0.95,
        volume: 1.0,        // Maximum volume
        language: "en-US",
        preUtteranceDelay: 0.0,
        postUtteranceDelay: 0.1
    )
}

// MARK: - Morpheus Voice

/// Handles voice output for Morpheus pivotal moment alerts.
/// Uses a distinct, authoritative voice profile to differentiate from Trinity.
final class MorpheusVoice: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private let synthesizer: AVSpeechSynthesizer
    private var currentProfile: VoiceProfile
    private var completionHandler: (() -> Void)?
    private var selectedVoice: AVSpeechSynthesisVoice?

    // MARK: - Alert Sound

    private var alertSoundEnabled: Bool = true

    // MARK: - Initialization

    init(profile: VoiceProfile = .morpheus) {
        self.synthesizer = AVSpeechSynthesizer()
        self.currentProfile = profile
        super.init()
        self.synthesizer.delegate = self
        self.selectedVoice = selectVoice(for: profile)
        configureAudioSession()
    }

    // MARK: - Audio Session

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Use .playback with .interruptSpokenAudioAndMixWithOthers for urgent alerts
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.interruptSpokenAudioAndMixWithOthers]
            )
        } catch {
            print("[MorpheusVoice] Audio session configuration failed: \(error)")
        }
    }

    // MARK: - Speech

    /// Speak a message with Morpheus's authoritative voice.
    /// - Parameter text: The text to speak.
    func speak(_ text: String) async {
        // Interrupt any current speech — Morpheus takes priority
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Activate audio session for alert
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = buildUtterance(for: text)

        await withCheckedContinuation { continuation in
            completionHandler = {
                continuation.resume()
            }
            synthesizer.speak(utterance)
        }
    }

    /// Speak a critical alert with elevated urgency parameters.
    /// - Parameter text: The critical alert text.
    func speakCritical(_ text: String) async {
        let previousProfile = currentProfile
        currentProfile = .morpheusCritical
        selectedVoice = selectVoice(for: .morpheusCritical)

        // TODO: Play alert chime before critical voice
        if alertSoundEnabled {
            playAlertChime(severity: .critical)
        }

        await speak(text)

        currentProfile = previousProfile
        selectedVoice = selectVoice(for: previousProfile)
    }

    /// Speak a pivotal moment alert with severity-appropriate parameters.
    /// - Parameters:
    ///   - text: The alert text.
    ///   - severity: The moment severity.
    func speakAlert(_ text: String, severity: MomentSeverity) async {
        if alertSoundEnabled {
            playAlertChime(severity: severity)
        }

        switch severity {
        case .critical:
            await speakCritical(text)
        case .urgent:
            // Slightly elevated from normal Morpheus voice
            let urgentProfile = VoiceProfile(
                identifier: "com.mtrx.morpheus.urgent",
                name: "Morpheus Urgent",
                rate: 0.46,
                pitch: 0.92,
                volume: 0.95,
                language: currentProfile.language,
                preUtteranceDelay: 0.02,
                postUtteranceDelay: 0.2
            )
            let previousProfile = currentProfile
            currentProfile = urgentProfile
            selectedVoice = selectVoice(for: urgentProfile)
            await speak(text)
            currentProfile = previousProfile
            selectedVoice = selectVoice(for: previousProfile)
        case .important, .advisory:
            await speak(text)
        }
    }

    /// Stop all speech immediately.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        completionHandler?()
        completionHandler = nil
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

    private func selectVoice(for profile: VoiceProfile) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == profile.language }

        // Prefer a different voice identifier than Trinity for distinction
        // Try to find a deeper/male voice for Morpheus
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return voices.first
    }

    private func playAlertChime(severity: MomentSeverity) {
        // TODO: Implement alert chime playback using AVAudioPlayer
        // Different chimes for different severity levels:
        // - critical: sharp, attention-grabbing tone
        // - urgent: firm double-tone
        // - important: single notification tone
        // - advisory: soft chime
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension MorpheusVoice: AVSpeechSynthesizerDelegate {

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
