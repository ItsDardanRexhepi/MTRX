// VoiceManager.swift
// MTRX Apple Integration — Presence
// AVFoundation playback for Trinity, Morpheus, and Oracle AI personas

import AVFoundation
import Foundation

// MARK: - Voice Manager

final class VoiceManager: NSObject {

    // MARK: - Shared Instance

    static let shared = VoiceManager()

    // MARK: - Properties

    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private let synthesizer = AVSpeechSynthesizer()
    private var currentPersona: AIPersona = .trinity

    // MARK: - AI Personas

    enum AIPersona: String, CaseIterable {
        case trinity
        case morpheus
        case oracle

        var voiceIdentifier: String {
            switch self {
            case .trinity: return "com.apple.voice.compact.en-US.Samantha"
            case .morpheus: return "com.apple.voice.compact.en-US.Daniel"
            case .oracle: return "com.apple.voice.compact.en-US.Karen"
            }
        }

        var pitch: Float {
            switch self {
            case .trinity: return 1.1
            case .morpheus: return 0.85
            case .oracle: return 1.0
            }
        }

        var rate: Float {
            switch self {
            case .trinity: return 0.52
            case .morpheus: return 0.46
            case .oracle: return 0.50
            }
        }

        var volume: Float {
            switch self {
            case .trinity: return 0.9
            case .morpheus: return 1.0
            case .oracle: return 0.85
            }
        }
    }

    // MARK: - Audio Session

    /// Configures the audio session for voice playback.
    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try session.setActive(true)
    }

    /// Deactivates the audio session.
    func deactivateAudioSession() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Text-to-Speech

    /// Speaks a message using the specified AI persona voice.
    func speak(_ text: String, as persona: AIPersona = .trinity) {
        currentPersona = persona

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: persona.voiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.pitchMultiplier = persona.pitch
        utterance.rate = persona.rate
        utterance.volume = persona.volume
        utterance.preUtteranceDelay = 0.1
        utterance.postUtteranceDelay = 0.2

        synthesizer.delegate = self
        synthesizer.speak(utterance)
    }

    /// Speaks a transaction confirmation using the appropriate persona.
    func speakTransactionConfirmation(amount: String, symbol: String, type: String, persona: AIPersona = .trinity) {
        let message: String
        switch persona {
        case .trinity:
            message = "Transaction confirmed. \(amount) \(symbol) \(type) successfully processed."
        case .morpheus:
            message = "The transaction is complete. \(amount) \(symbol) has been \(type)."
        case .oracle:
            message = "Confirmation received. \(amount) \(symbol) \(type) operation finalized."
        }
        speak(message, as: persona)
    }

    // MARK: - Audio File Playback

    /// Plays a bundled audio file for UI sound effects.
    func playSound(named name: String, fileExtension: String = "wav") {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayers[name] = player
            player.delegate = self
            player.prepareToPlay()
            player.play()
        } catch {
            // Silent failure for sound effects
        }
    }

    /// Plays a transaction notification sound.
    func playTransactionSound(_ type: TransactionSoundType) {
        playSound(named: type.fileName)
    }

    // MARK: - Audio Engine

    /// Starts the audio engine for real-time audio processing.
    func startEngine() throws {
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)
        try audioEngine.start()
    }

    /// Stops the audio engine.
    func stopEngine() {
        audioEngine.stop()
        playerNode.stop()
    }

    /// Plays audio data through the audio engine with optional effects.
    func playAudioData(_ data: Data, format: AVAudioFormat) throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(data.count) / format.streamDescription.pointee.mBytesPerFrame) else {
            throw VoiceError.bufferCreationFailed
        }

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            memcpy(buffer.floatChannelData?[0], baseAddress, data.count)
            buffer.frameLength = buffer.frameCapacity
        }

        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }

    // MARK: - Control

    /// Stops all audio playback.
    func stopAll() {
        synthesizer.stopSpeaking(at: .immediate)
        playerNode.stop()
        audioPlayers.values.forEach { $0.stop() }
        audioPlayers.removeAll()
    }

    /// Pauses speech synthesis.
    func pauseSpeech() {
        synthesizer.pauseSpeaking(at: .word)
    }

    /// Continues paused speech synthesis.
    func continueSpeech() {
        synthesizer.continueSpeaking()
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension VoiceManager: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? deactivateAudioSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        try? deactivateAudioSession()
    }
}

// MARK: - AVAudioPlayerDelegate

extension VoiceManager: AVAudioPlayerDelegate {

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        audioPlayers = audioPlayers.filter { $0.value !== player }
    }
}

// MARK: - Transaction Sound Type

enum TransactionSoundType: String {
    case sent = "tx_sent"
    case received = "tx_received"
    case confirmed = "tx_confirmed"
    case failed = "tx_failed"
    case alert = "tx_alert"

    var fileName: String { rawValue }
}

// MARK: - Voice Error

enum VoiceError: LocalizedError {
    case bufferCreationFailed
    case engineStartFailed
    case audioSessionFailed

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed: return "Failed to create audio buffer"
        case .engineStartFailed: return "Failed to start audio engine"
        case .audioSessionFailed: return "Failed to configure audio session"
        }
    }
}
