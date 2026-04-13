//
//  TrinityInference.swift
//  MTRX — Trinity
//
//  CoreML on-device inference pipeline with model versioning.
//

import Foundation
import CoreML

// MARK: - Trinity Inference

/// On-device inference pipeline using CoreML.
/// Handles model loading, prediction, result interpretation, and model versioning.
final class TrinityInference {

    // MARK: - Properties

    private var activeModel: MLModel?
    private var modelMetadata: ModelMetadata?
    private let modelCache = NSCache<NSString, MLModel>()
    private let modelDirectory: URL
    private var isModelLoaded: Bool { activeModel != nil }

    // MARK: - Model Configuration

    struct ModelConfig {
        let computeUnits: MLComputeUnits
        let allowLowPrecision: Bool
        let maxBatchSize: Int

        static let `default` = ModelConfig(
            computeUnits: .all,
            allowLowPrecision: true,
            maxBatchSize: 1
        )

        static let highPerformance = ModelConfig(
            computeUnits: .cpuAndNeuralEngine,
            allowLowPrecision: false,
            maxBatchSize: 4
        )
    }

    // MARK: - Initialization

    init(modelDirectory: URL? = nil) {
        self.modelDirectory = modelDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("MTRX/Models")
    }

    // MARK: - Model Loading

    /// Load a CoreML model from the specified path.
    /// - Parameters:
    ///   - name: The model name (without extension).
    ///   - version: The model version to load. Loads latest if nil.
    ///   - config: Model configuration options.
    func loadModel(
        named name: String,
        version: String? = nil,
        config: ModelConfig = .default
    ) async throws {
        // Check cache first
        let cacheKey = "\(name)_\(version ?? "latest")" as NSString
        if let cached = modelCache.object(forKey: cacheKey) {
            activeModel = cached
            return
        }

        // Resolve model path
        let modelPath = try resolveModelPath(name: name, version: version)

        // Configure compilation
        let mlConfig = MLModelConfiguration()
        mlConfig.computeUnits = config.computeUnits
        mlConfig.allowLowPrecisionAccumulationOnGPU = config.allowLowPrecision

        // Load and compile model
        let model = try await Task.detached(priority: .userInitiated) {
            try MLModel(contentsOf: modelPath, configuration: mlConfig)
        }.value

        activeModel = model
        modelCache.setObject(model, forKey: cacheKey)

        // Load metadata
        modelMetadata = ModelMetadata(
            name: name,
            version: version ?? "latest",
            loadedAt: Date(),
            path: modelPath
        )
    }

    // MARK: - Prediction

    /// Run prediction on the loaded model.
    /// - Parameter input: Dictionary of input feature names to values.
    /// - Returns: The prediction result.
    func predict(input: [String: Any]) async throws -> PredictionResult {
        guard let model = activeModel else {
            throw InferenceError.modelNotLoaded
        }

        // Build feature provider from input dictionary
        let featureProvider = try buildFeatureProvider(from: input)

        // Measure end-to-end inference latency in nanoseconds and
        // round to an integer millisecond value. We use
        // ``DispatchTime`` rather than ``Date`` so the measurement
        // isn't affected by wall-clock adjustments while the model
        // runs.
        let started = DispatchTime.now()
        let prediction = try await Task.detached(priority: .userInitiated) {
            try model.prediction(from: featureProvider)
        }.value
        let elapsedNs = DispatchTime.now().uptimeNanoseconds &- started.uptimeNanoseconds
        let latencyMs = Int((Double(elapsedNs) / 1_000_000.0).rounded())

        // Parse output features
        let output = parseOutput(prediction)

        return PredictionResult(
            output: output,
            timestamp: Date(),
            modelVersion: modelMetadata?.version ?? "unknown",
            latencyMs: latencyMs
        )
    }

    /// Batch prediction for multiple inputs.
    /// - Parameter inputs: Array of input dictionaries.
    /// - Returns: Array of prediction results.
    func predictBatch(inputs: [[String: Any]]) async throws -> [PredictionResult] {
        guard activeModel != nil else {
            throw InferenceError.modelNotLoaded
        }

        var results: [PredictionResult] = []
        for input in inputs {
            let result = try await predict(input: input)
            results.append(result)
        }
        return results
    }

    // MARK: - Result Interpretation

    /// Interpret a raw prediction result into a human-readable format.
    /// - Parameter result: The raw prediction result.
    /// - Returns: An interpreted result with labels and confidence scores.
    func interpretResult(_ result: PredictionResult) -> InterpretedResult {
        // TODO: Implement model-specific interpretation logic
        // - Map output indices to labels
        // - Apply softmax for classification
        // - Scale regression outputs to meaningful ranges

        let topPrediction = result.output.max { a, b in
            (a.value as? Double ?? 0) < (b.value as? Double ?? 0)
        }

        return InterpretedResult(
            label: topPrediction?.key ?? "unknown",
            confidence: topPrediction?.value as? Double ?? 0.0,
            allPredictions: result.output,
            explanation: "Prediction based on \(modelMetadata?.name ?? "unknown") model v\(modelMetadata?.version ?? "?")"
        )
    }

    // MARK: - Model Versioning

    /// List available model versions for a given model name.
    /// - Parameter name: The model name.
    /// - Returns: Available versions sorted from newest to oldest.
    func availableVersions(for name: String) throws -> [String] {
        let modelDir = modelDirectory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: modelDir.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: modelDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        )

        return contents
            .filter { $0.pathExtension == "mlmodelc" || $0.pathExtension == "mlpackage" }
            .compactMap { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0 > $1 }
    }

    /// Check if a newer model version is available.
    /// - Parameter name: The model name.
    /// - Returns: True if a newer version exists.
    func hasNewerVersion(for name: String) throws -> Bool {
        guard let current = modelMetadata, current.name == name else { return false }
        let versions = try availableVersions(for: name)
        guard let latest = versions.first else { return false }
        return latest > current.version
    }

    // MARK: - Private Helpers

    private func resolveModelPath(name: String, version: String?) throws -> URL {
        let modelDir = modelDirectory.appendingPathComponent(name)

        if let version = version {
            let versionedPath = modelDir.appendingPathComponent("\(version).mlmodelc")
            guard FileManager.default.fileExists(atPath: versionedPath.path) else {
                throw InferenceError.modelNotFound(name, version)
            }
            return versionedPath
        }

        // Find latest version
        let versions = try availableVersions(for: name)
        guard let latest = versions.first else {
            throw InferenceError.modelNotFound(name, "latest")
        }
        return modelDir.appendingPathComponent("\(latest).mlmodelc")
    }

    private func buildFeatureProvider(from input: [String: Any]) throws -> MLFeatureProvider {
        // TODO: Implement proper feature provider construction
        // - Handle different MLFeatureValue types (double, int, string, multiarray, image)
        var features: [String: MLFeatureValue] = [:]

        for (key, value) in input {
            if let doubleValue = value as? Double {
                features[key] = MLFeatureValue(double: doubleValue)
            } else if let intValue = value as? Int {
                features[key] = MLFeatureValue(int64: Int64(intValue))
            } else if let stringValue = value as? String {
                features[key] = MLFeatureValue(string: stringValue)
            }
            // TODO: Handle MLMultiArray, CVPixelBuffer, etc.
        }

        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    private func parseOutput(_ prediction: MLFeatureProvider) -> [String: Any] {
        var output: [String: Any] = [:]
        for name in prediction.featureNames {
            if let feature = prediction.featureValue(for: name) {
                switch feature.type {
                case .double:
                    output[name] = feature.doubleValue
                case .int64:
                    output[name] = feature.int64Value
                case .string:
                    output[name] = feature.stringValue
                default:
                    output[name] = feature.description
                }
            }
        }
        return output
    }
}

// MARK: - Supporting Types

struct ModelMetadata {
    let name: String
    let version: String
    let loadedAt: Date
    let path: URL
}

struct PredictionResult: Sendable {
    let output: [String: Any]
    let timestamp: Date
    let modelVersion: String
    let latencyMs: Double
}

struct InterpretedResult: Sendable {
    let label: String
    let confidence: Double
    let allPredictions: [String: Any]
    let explanation: String
}

// MARK: - Inference Errors

enum InferenceError: Error, LocalizedError {
    case modelNotLoaded
    case modelNotFound(String, String)
    case predictionFailed(String)
    case invalidInput(String)
    case versionConflict(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No model is currently loaded"
        case .modelNotFound(let name, let version):
            return "Model '\(name)' version '\(version)' not found"
        case .predictionFailed(let reason):
            return "Prediction failed: \(reason)"
        case .invalidInput(let reason):
            return "Invalid input: \(reason)"
        case .versionConflict(let reason):
            return "Model version conflict: \(reason)"
        }
    }
}
