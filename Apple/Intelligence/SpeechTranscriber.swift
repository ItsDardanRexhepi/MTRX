// SpeechTranscriber.swift
// MTRX Apple Integration — Intelligence
// Real-time audio transcription (foreground only)

import Speech
import AVFoundation

// MARK: - Speech Transcriber

final class SpeechTranscriber: NSObject {

    // MARK: - Shared Instance

    static let shared = SpeechTranscriber()

    // MARK: - Properties

    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Silence-driven turn ending + a watchdog for the graceful finish.
    private var silenceWork: DispatchWorkItem?
    private var finishWatchdog: DispatchWorkItem?

    private var onPartialResult: ((String) -> Void)?
    private var onFinalResult: ((TranscriptionResult) -> Void)?
    private var onError: ((Error) -> Void)?

    // MARK: - State

    enum TranscriberState {
        case idle
        case requesting
        case recording
        case processing
        case error(Error)
    }

    private(set) var state: TranscriberState = .idle

    // MARK: - Transcription Result

    struct TranscriptionResult {
        let text: String
        let confidence: Float
        let segments: [TranscriptionSegment]
        let duration: TimeInterval
        let isFinal: Bool
    }

    struct TranscriptionSegment {
        let text: String
        let timestamp: TimeInterval
        let duration: TimeInterval
        let confidence: Float
    }

    // MARK: - Initialization

    private override init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
        super.init()
        speechRecognizer.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    completion(true)
                case .denied, .restricted, .notDetermined:
                    completion(false)
                @unknown default:
                    completion(false)
                }
            }
        }
    }

    var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    // MARK: - Start Streaming Transcription

    func startTranscription(
        onPartial: @escaping (String) -> Void,
        onFinal: @escaping (TranscriptionResult) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        guard speechRecognizer.isAvailable else {
            throw TranscriberError.recognizerUnavailable
        }

        // Cancel any existing task
        stopTranscription()

        self.onPartialResult = onPartial
        self.onFinalResult = onFinal
        self.onError = onError

        state = .requesting

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw TranscriberError.requestCreationFailed
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = true // On-device only for privacy

        if #available(iOS 16.0, *) {
            recognitionRequest.addsPunctuation = true
        }

        // Start recognition task
        let startTime = Date()

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            // Route every callback onto the main queue so the engine, timers, and
            // state are only ever touched from one place.
            DispatchQueue.main.async {
                self?.handleRecognition(result: result, error: error, startTime: startTime)
            }
        }

        // Configure audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        state = .recording
        // Give the user a few seconds to start talking; after that a pause ends the turn.
        scheduleSilenceFinish(after: 4.0)
    }

    // MARK: - Recognition handling (always on the main queue)

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?, startTime: Date) {
        if let error = error {
            // A deliberate cancel (stopTranscription) surfaces here as an error after
            // we've already gone idle — don't nag the user about that.
            switch state {
            case .recording, .processing: onError?(error)
            default: break
            }
            cleanupAfterFinish()
            return
        }
        guard let result = result else { return }
        if result.isFinal {
            let segments = result.bestTranscription.segments.map { seg in
                TranscriptionSegment(text: seg.substring, timestamp: seg.timestamp,
                                     duration: seg.duration, confidence: seg.confidence)
            }
            let transcription = TranscriptionResult(
                text: result.bestTranscription.formattedString,
                confidence: segments.map(\.confidence).reduce(0, +) / Float(max(segments.count, 1)),
                segments: segments,
                duration: Date().timeIntervalSince(startTime),
                isFinal: true
            )
            onFinalResult?(transcription)
            cleanupAfterFinish()
        } else {
            state = .recording
            onPartialResult?(result.bestTranscription.formattedString)
            scheduleSilenceFinish(after: 1.8)   // reset the pause timer on every word
        }
    }

    /// End the current turn after `seconds` of no new words.
    private func scheduleSilenceFinish(after seconds: TimeInterval) {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.finishTranscription() }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Gracefully end capture so the recognizer delivers a FINAL result (unlike
    /// stopTranscription, which cancels and yields nothing). Ends a spoken turn.
    func finishTranscription() {
        guard recognitionTask != nil, case .recording = state else { return }
        state = .processing
        silenceWork?.cancel(); silenceWork = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        // If the recognizer never returns a final, force an (empty) finish so the UI
        // never hangs in "processing".
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.recognitionTask != nil else { return }
            self.onFinalResult?(TranscriptionResult(text: "", confidence: 0, segments: [], duration: 0, isFinal: true))
            self.cleanupAfterFinish()
        }
        finishWatchdog = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: watchdog)
    }

    private func cleanupAfterFinish() {
        silenceWork?.cancel(); silenceWork = nil
        finishWatchdog?.cancel(); finishWatchdog = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Stop Transcription

    func stopTranscription() {
        silenceWork?.cancel(); silenceWork = nil
        finishWatchdog?.cancel(); finishWatchdog = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        state = .idle

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio Level Monitoring

    /// Returns the current audio input level for UI visualization.
    var currentAudioLevel: Float {
        guard audioEngine.isRunning else { return 0 }
        let channelData = audioEngine.inputNode.outputFormat(forBus: 0)
        return 0.0 // Placeholder: would compute RMS from buffer
    }

    // MARK: - Supported Locales

    static var supportedLocales: Set<Locale> {
        SFSpeechRecognizer.supportedLocales()
    }
}

// MARK: - SFSpeechRecognizerDelegate

extension SpeechTranscriber: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            state = .error(TranscriberError.recognizerUnavailable)
            stopTranscription()
        }
    }
}

// MARK: - Transcriber Error

enum TranscriberError: LocalizedError {
    case recognizerUnavailable
    case notAuthorized
    case requestCreationFailed
    case audioSessionFailed

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "Speech recognizer is not available"
        case .notAuthorized: return "Speech recognition not authorized"
        case .requestCreationFailed: return "Failed to create recognition request"
        case .audioSessionFailed: return "Failed to configure audio session"
        }
    }
}
