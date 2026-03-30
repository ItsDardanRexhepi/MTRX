//
//  OracleVoice.swift
//  MTRX — Oracle
//
//  AVFoundation voice playback for Oracle layer.
//  Distinct voice used exclusively for DardanAdvisory briefings.
//

import Foundation
import AVFoundation

// MARK: - Oracle Voice Profile

extension VoiceProfile {
    /// Oracle voice: measured, analytical, authoritative.
    /// Used exclusively for DardanAdvisory private briefings.
    /// Distinct from both Trinity (warm/conversational) and Morpheus (urgent/commanding).
    static let oracle = VoiceProfile(
        identifier: "com.mtrx.oracle",
        name: "Oracle",
        rate: 0.44,         // Deliberate, measured pace
        pitch: 0.95,        // Slightly deeper than neutral
        volume: 0.80,       // Moderate volume — private briefing
        language: "en-US",
        preUtteranceDelay: 0.3,   // Slight pause before speaking — gravitas
        postUtteranceDelay: 0.4   // Pause after for consideration
    )

    /// Oracle briefing opener voice — slightly slower for emphasis.
    static let oracleBriefingOpener = VoiceProfile(
        identifier: "com.mtrx.oracle.opener",
        name: "Oracle Briefing",
        rate: 0.40,
        pitch: 0.92,
        volume: 0.85,
        language: "en-US",
        preUtteranceDelay: 0.5,
        postUtteranceDelay: 0.5
    )
}

// MARK: - Oracle Voice

/// Voice output handler for Oracle layer private briefings.
/// Only used for DardanAdvisory briefings — never for general user interaction.
final class OracleVoice: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private let synthesizer: AVSpeechSynthesizer
    private var currentProfile: VoiceProfile
    private var completionHandler: (() -> Void)?
    private var selectedVoice: AVSpeechSynthesisVoice?
    private var isBriefingInProgress: Bool = false

    // MARK: - Initialization

    init(profile: VoiceProfile = .oracle) {
        self.synthesizer = AVSpeechSynthesizer()
        self.currentProfile = profile
        super.init()
        self.synthesizer.delegate = self
        self.selectedVoice = selectVoice(for: profile)
    }

    // MARK: - Audio Session

    private func configureAudioSessionForBriefing() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("[OracleVoice] Audio session configuration failed: \(error)")
        }
    }

    // MARK: - Speech

    /// Speak a text using Oracle's voice profile.
    /// - Parameter text: The text to speak.
    func speak(_ text: String) async {
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

    /// Deliver a full briefing with structured pacing and emphasis.
    /// - Parameter script: The briefing script to deliver.
    func speakBriefing(_ script: String) async {
        guard !isBriefingInProgress else { return }
        isBriefingInProgress = true
        defer { isBriefingInProgress = false }

        configureAudioSessionForBriefing()

        // Split script into segments for natural pacing
        let segments = segmentBriefing(script)

        for (index, segment) in segments.enumerated() {
            let profile: VoiceProfile
            if index == 0 {
                // Use opener profile for the first segment
                profile = .oracleBriefingOpener
            } else {
                profile = .oracle
            }

            let previousProfile = currentProfile
            currentProfile = profile
            selectedVoice = selectVoice(for: profile)

            await speak(segment)

            currentProfile = previousProfile
            selectedVoice = selectVoice(for: previousProfile)

            // Brief pause between sections
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        }
    }

    /// Stop the current briefing.
    func stopBriefing() {
        isBriefingInProgress = false
        synthesizer.stopSpeaking(at: .word)
        completionHandler?()
        completionHandler = nil
    }

    /// Pause the current briefing.
    func pauseBriefing() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Resume the paused briefing.
    func resumeBriefing() {
        guard synthesizer.isPaused else { return }
        synthesizer.continueSpeaking()
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

        // Select a distinct voice from Trinity and Morpheus
        // Prefer a different voice identifier for Oracle
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return voices.first
    }

    /// Segment a briefing script into natural sections for paced delivery.
    /// - Parameter script: The full briefing script.
    /// - Returns: Array of script segments.
    private func segmentBriefing(_ script: String) -> [String] {
        // Split on section markers (sentences ending with periods followed by title-like text)
        let sentences = script.components(separatedBy: ". ")
        var segments: [String] = []
        var currentSegment: [String] = []

        for sentence in sentences {
            currentSegment.append(sentence)

            // Create a new segment every 3-4 sentences for natural pacing
            if currentSegment.count >= 3 {
                segments.append(currentSegment.joined(separator: ". ") + ".")
                currentSegment.removeAll()
            }
        }

        // Append remaining sentences
        if !currentSegment.isEmpty {
            segments.append(currentSegment.joined(separator: ". ") + ".")
        }

        return segments
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension OracleVoice: AVSpeechSynthesizerDelegate {

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
