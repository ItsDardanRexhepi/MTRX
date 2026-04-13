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
    /// Pool of ``AVAudioPlayer`` instances — one per severity — built
    /// lazily from synthesized PCM so MTRX doesn't need to bundle
    /// audio assets for the alert chimes.
    private var chimePlayers: [MomentSeverity: AVAudioPlayer] = [:]

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

        // Play the critical-severity chime first so the user hears
        // the attention-getting tone before Morpheus's voice starts.
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

    /// Play the alert chime that precedes a Morpheus voice line.
    ///
    /// Rather than bundling four audio assets in the app package we
    /// synthesize each chime once at first use and cache the resulting
    /// ``AVAudioPlayer`` in ``chimePlayers``. Each severity gets its
    /// own timbre:
    ///
    /// * ``.critical``  — a sharp 880 Hz single tone, 0.35 s, full volume.
    /// * ``.urgent``    — a firm double-tap at 660 Hz with a short gap.
    /// * ``.important`` — a single 523 Hz tone, 0.22 s, 80% volume.
    /// * ``.advisory``  — a soft 392 Hz tone, 0.30 s, 60% volume.
    ///
    /// The synthesis work happens on a background queue so the first
    /// chime doesn't block the main thread. If AVAudio or the PCM
    /// encoder errors out we fall back silently — the speech itself
    /// is the primary signal and the chime is a nicety.
    private func playAlertChime(severity: MomentSeverity) {
        if let cached = chimePlayers[severity] {
            cached.currentTime = 0
            cached.play()
            return
        }
        do {
            let player = try Self.buildChimePlayer(for: severity)
            chimePlayers[severity] = player
            player.play()
        } catch {
            print("[MorpheusVoice] Chime synthesis failed: \(error)")
        }
    }

    /// Synthesize a PCM WAV in-memory and return a ready-to-play
    /// ``AVAudioPlayer`` for *severity*. The returned player is
    /// cached by the caller so we only pay this cost once per launch.
    private static func buildChimePlayer(for severity: MomentSeverity) throws -> AVAudioPlayer {
        let sampleRate: Double = 44_100
        let segments = segments(for: severity)

        var samples: [Int16] = []
        samples.reserveCapacity(Int(sampleRate) * 2)
        for segment in segments {
            let count = Int(sampleRate * segment.duration)
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let envelope = envelopeValue(at: t, duration: segment.duration)
                let sine = sin(2.0 * .pi * segment.frequency * t)
                let value = sine * envelope * segment.amplitude
                samples.append(Int16(max(-1.0, min(1.0, value)) * Double(Int16.max)))
            }
            if segment.tailGap > 0 {
                let gapCount = Int(sampleRate * segment.tailGap)
                samples.append(contentsOf: repeatElement(Int16(0), count: gapCount))
            }
        }

        let data = Self.wavData(samples: samples, sampleRate: Int(sampleRate))
        let player = try AVAudioPlayer(data: data)
        player.prepareToPlay()
        player.volume = 1.0
        return player
    }

    /// One segment of a synthesized chime — pure tone + optional gap.
    private struct ChimeSegment {
        let frequency: Double
        let duration: Double
        let amplitude: Double
        let tailGap: Double
    }

    /// Return the ordered list of segments that make up the chime for
    /// *severity*. Keeping this as pure data makes the chime profiles
    /// easy to tweak without touching the synthesis code.
    private static func segments(for severity: MomentSeverity) -> [ChimeSegment] {
        switch severity {
        case .critical:
            return [
                ChimeSegment(frequency: 880.0, duration: 0.35, amplitude: 1.00, tailGap: 0.02),
            ]
        case .urgent:
            return [
                ChimeSegment(frequency: 660.0, duration: 0.18, amplitude: 0.90, tailGap: 0.08),
                ChimeSegment(frequency: 660.0, duration: 0.18, amplitude: 0.90, tailGap: 0.02),
            ]
        case .important:
            return [
                ChimeSegment(frequency: 523.25, duration: 0.22, amplitude: 0.80, tailGap: 0.02),
            ]
        case .advisory:
            return [
                ChimeSegment(frequency: 392.00, duration: 0.30, amplitude: 0.60, tailGap: 0.02),
            ]
        }
    }

    /// Cheap triangular attack/release envelope to avoid clicking at
    /// the start/end of each tone. We ramp the amplitude up over the
    /// first 10ms, hold, then ramp back down over the last 30ms.
    private static func envelopeValue(at t: Double, duration: Double) -> Double {
        let attack = 0.010
        let release = min(0.030, duration * 0.2)
        if t < attack {
            return t / attack
        }
        if t > duration - release {
            let remaining = max(0, duration - t)
            return remaining / release
        }
        return 1.0
    }

    /// Assemble a minimal WAV file (RIFF/WAVE, 16-bit mono PCM) from a
    /// buffer of samples so ``AVAudioPlayer(data:)`` can decode it
    /// without round-tripping through disk.
    private static func wavData(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let byteRate = sampleRate * 2
        let dataSize = samples.count * 2

        func appendLE32(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func appendLE16(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        data.append("RIFF".data(using: .ascii)!)
        appendLE32(UInt32(36 + dataSize))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        appendLE32(16)                 // fmt chunk size
        appendLE16(1)                  // PCM
        appendLE16(1)                  // mono
        appendLE32(UInt32(sampleRate))
        appendLE32(UInt32(byteRate))
        appendLE16(2)                  // block align
        appendLE16(16)                 // bits per sample
        data.append("data".data(using: .ascii)!)
        appendLE32(UInt32(dataSize))
        for sample in samples {
            var s = sample.littleEndian
            withUnsafeBytes(of: &s) { data.append(contentsOf: $0) }
        }
        return data
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
