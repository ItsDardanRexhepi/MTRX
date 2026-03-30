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
            guard let self = self else { return }

            if let error = error {
                self.state = .error(error)
                self.onError?(error)
                self.stopTranscription()
                return
            }

            guard let result = result else { return }

            if result.isFinal {
                let segments = result.bestTranscription.segments.map { segment in
                    TranscriptionSegment(
                        text: segment.substring,
                        timestamp: segment.timestamp,
                        duration: segment.duration,
                        confidence: segment.confidence
                    )
                }

                let transcription = TranscriptionResult(
                    text: result.bestTranscription.formattedString,
                    confidence: segments.map(\.confidence).reduce(0, +) / Float(max(segments.count, 1)),
                    segments: segments,
                    duration: Date().timeIntervalSince(startTime),
                    isFinal: true
                )

                self.state = .idle
                self.onFinalResult?(transcription)
            } else {
                self.state = .recording
                self.onPartialResult?(result.bestTranscription.formattedString)
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
    }

    // MARK: - Stop Transcription

    func stopTranscription() {
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
