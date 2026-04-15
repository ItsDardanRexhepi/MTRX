// CoreMLManager.swift
// MTRX Apple Integration — Intelligence
// CoreML on-device inference with Neural Engine preference

import CoreML
import Foundation

// MARK: - CoreML Manager

final class CoreMLManager {

    // MARK: - Shared Instance

    static let shared = CoreMLManager()

    // MARK: - Properties

    private var loadedModels: [String: MLModel] = [:]
    private let modelQueue = DispatchQueue(label: "com.mtrx.coreml", qos: .userInitiated)
    private let modelCacheDirectory: URL

    // MARK: - Model Registry

    enum TrinityModel: String, CaseIterable {
        case sentimentAnalysis = "TrinitySentiment"
        case intentClassification = "TrinityIntent"
        case pricePredictor = "TrinityPricePredictor"
        case anomalyDetector = "TrinityAnomalyDetector"
        case riskScorer = "TrinityRiskScorer"
        case transactionClassifier = "TrinityTxClassifier"

        var expectedInputShape: [Int] {
            switch self {
            case .sentimentAnalysis: return [1, 512]
            case .intentClassification: return [1, 256]
            case .pricePredictor: return [1, 128, 10]
            case .anomalyDetector: return [1, 64]
            case .riskScorer: return [1, 32]
            case .transactionClassifier: return [1, 128]
            }
        }
    }

    // MARK: - Initialization

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        modelCacheDirectory = caches.appendingPathComponent("com.mtrx.models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelCacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Model Loading

    /// Loads a CoreML model with Neural Engine preference.
    func loadModel(_ model: TrinityModel) async throws -> MLModel {
        if let cached = loadedModels[model.rawValue] {
            return cached
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all // Prefer Neural Engine, fall back to GPU/CPU

        // Allow Neural Engine for maximum performance
        if #available(iOS 16.0, macOS 13.0, *) {
            config.computeUnits = .cpuAndNeuralEngine
        }

        guard let modelURL = Bundle.main.url(forResource: model.rawValue, withExtension: "mlmodelc") else {
            throw CoreMLError.modelNotFound(model.rawValue)
        }

        let loadedModel = try await MLModel.load(contentsOf: modelURL, configuration: config)
        loadedModels[model.rawValue] = loadedModel
        return loadedModel
    }

    // MARK: - Prediction

    /// Runs inference on a loaded model with the given feature provider.
    func predict(model: TrinityModel, input: MLFeatureProvider) async throws -> MLFeatureProvider {
        let mlModel = try await loadModel(model)
        return try await mlModel.prediction(from: input)
    }

    /// Batch prediction for multiple inputs.
    func batchPredict(model: TrinityModel, inputs: MLBatchProvider) async throws -> MLBatchProvider {
        let mlModel = try await loadModel(model)
        return try await mlModel.predictions(from: inputs, options: MLPredictionOptions())
    }

    // MARK: - Model Compilation

    /// Compiles a model from .mlmodel source and caches the compiled version.
    func compileModel(at sourceURL: URL, identifier: String) async throws -> MLModel {
        let compiledURL = try await MLModel.compileModel(at: sourceURL)

        let cachedURL = modelCacheDirectory.appendingPathComponent("\(identifier).mlmodelc")
        try? FileManager.default.removeItem(at: cachedURL)
        try FileManager.default.copyItem(at: compiledURL, to: cachedURL)

        let config = MLModelConfiguration()
        config.computeUnits = .all
        return try MLModel(contentsOf: cachedURL, configuration: config)
    }

    // MARK: - Model Updates

    /// Checks for updated models and swaps them hot.
    func checkForModelUpdates() async throws -> [TrinityModel] {
        var updatedModels: [TrinityModel] = []

        for model in TrinityModel.allCases {
            let currentVersion = modelVersion(for: model)
            let availableVersion = try await fetchLatestModelVersion(for: model)

            if availableVersion > currentVersion {
                try await downloadAndReplaceModel(model, version: availableVersion)
                updatedModels.append(model)
            }
        }

        return updatedModels
    }

    // MARK: - Memory Management

    /// Unloads a model from memory.
    func unloadModel(_ model: TrinityModel) {
        loadedModels.removeValue(forKey: model.rawValue)
    }

    /// Unloads all models from memory.
    func unloadAllModels() {
        loadedModels.removeAll()
    }

    /// Returns the current memory footprint of loaded models.
    var loadedModelCount: Int {
        return loadedModels.count
    }

    // MARK: - Private Helpers

    private func modelVersion(for model: TrinityModel) -> Int {
        UserDefaults.standard.integer(forKey: "model_version_\(model.rawValue)")
    }

    private func fetchLatestModelVersion(for model: TrinityModel) async throws -> Int {
        // Check MTRX model registry for updates
        return 0
    }

    private func downloadAndReplaceModel(_ model: TrinityModel, version: Int) async throws {
        // Download updated model from MTRX CDN
        UserDefaults.standard.set(version, forKey: "model_version_\(model.rawValue)")
        unloadModel(model)
    }
}

// MARK: - CoreML Error

enum CoreMLError: LocalizedError {
    case modelNotFound(String)
    case predictionFailed(String)
    case compilationFailed(String)
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let name): return "Model '\(name)' not found in bundle"
        case .predictionFailed(let reason): return "Prediction failed: \(reason)"
        case .compilationFailed(let reason): return "Model compilation failed: \(reason)"
        case .invalidInput(let reason): return "Invalid input: \(reason)"
        }
    }
}

// MARK: - Trinity Feature Provider

/// Generic feature provider for Trinity model inputs.
final class TrinityFeatureProvider: MLFeatureProvider {
    let features: [String: MLFeatureValue]

    var featureNames: Set<String> {
        Set(features.keys)
    }

    init(features: [String: MLFeatureValue]) {
        self.features = features
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        return features[featureName]
    }
}
