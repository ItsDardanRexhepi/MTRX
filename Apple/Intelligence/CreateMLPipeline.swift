// CreateMLPipeline.swift
// MTRX Apple Integration — Intelligence
// On-device model training pipeline using CreateML

import CreateML
import CoreML
import Foundation

// MARK: - CreateML Pipeline

final class CreateMLPipeline {

    // MARK: - Shared Instance

    static let shared = CreateMLPipeline()

    // MARK: - Properties

    private let trainingQueue = DispatchQueue(label: "com.mtrx.createml.training", qos: .background)
    private let modelOutputDirectory: URL
    private var activeTrainingSessions: [String: TrainingSession] = [:]

    // MARK: - Training Configuration

    struct TrainingConfiguration {
        let modelType: ModelType
        let maxIterations: Int
        let validationFraction: Double
        let batchSize: Int
        let learningRate: Double

        static var defaultConfig: TrainingConfiguration {
            TrainingConfiguration(
                modelType: .tabularClassifier,
                maxIterations: 100,
                validationFraction: 0.2,
                batchSize: 32,
                learningRate: 0.001
            )
        }
    }

    enum ModelType {
        case tabularClassifier
        case tabularRegressor
        case textClassifier
        case timeSeriesForecaster
    }

    // MARK: - Training Session

    struct TrainingSession {
        let id: String
        let modelType: ModelType
        let startTime: Date
        var progress: Double
        var status: TrainingStatus
    }

    enum TrainingStatus {
        case preparing
        case training(iteration: Int, totalIterations: Int)
        case validating
        case completed(accuracy: Double)
        case failed(Error)
    }

    // MARK: - Initialization

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        modelOutputDirectory = documents.appendingPathComponent("com.mtrx.trained_models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelOutputDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Transaction Classification Training

    /// Trains a transaction classifier from user's transaction history.
    func trainTransactionClassifier(
        from transactions: [(features: [String: Any], label: String)],
        config: TrainingConfiguration = .defaultConfig
    ) async throws -> MLModel {
        let sessionId = UUID().uuidString
        activeTrainingSessions[sessionId] = TrainingSession(
            id: sessionId,
            modelType: .tabularClassifier,
            startTime: Date(),
            progress: 0,
            status: .preparing
        )

        // Convert transaction data to MLDataTable
        let dataTable = try buildDataTable(from: transactions)

        // Split into training and validation
        let (trainingData, validationData) = dataTable.randomSplit(by: config.validationFraction)

        // Train the classifier
        activeTrainingSessions[sessionId]?.status = .training(iteration: 0, totalIterations: config.maxIterations)

        let classifier = try MLBoostedTreeClassifier(
            trainingData: trainingData,
            targetColumn: "label",
            featureColumns: nil
        )

        // Evaluate
        activeTrainingSessions[sessionId]?.status = .validating
        let evaluation = classifier.evaluation(on: validationData)
        let accuracy = 1.0 - evaluation.classificationError

        activeTrainingSessions[sessionId]?.status = .completed(accuracy: accuracy)

        // Export compiled model
        let outputURL = modelOutputDirectory.appendingPathComponent("TxClassifier_\(sessionId).mlmodel")
        try classifier.write(to: outputURL)

        let compiledURL = try MLModel.compileModel(at: outputURL)
        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = .all
        return try MLModel(contentsOf: compiledURL, configuration: modelConfig)
    }

    // MARK: - Price Prediction Training

    /// Trains a price prediction regressor from historical price data.
    func trainPricePredictor(
        from priceHistory: [(features: [String: Double], price: Double)],
        config: TrainingConfiguration = .defaultConfig
    ) async throws -> MLModel {
        let sessionId = UUID().uuidString

        var featureColumns: [[String: Double]] = []
        var targets: [Double] = []

        for entry in priceHistory {
            featureColumns.append(entry.features)
            targets.append(entry.price)
        }

        let dataTable = try buildRegressionDataTable(features: featureColumns, targets: targets)
        let (trainingData, validationData) = dataTable.randomSplit(by: config.validationFraction)

        let regressor = try MLBoostedTreeRegressor(
            trainingData: trainingData,
            targetColumn: "price"
        )

        let evaluation = regressor.evaluation(on: validationData)
        let rmse = evaluation.rootMeanSquaredError

        let outputURL = modelOutputDirectory.appendingPathComponent("PricePredictor_\(sessionId).mlmodel")
        try regressor.write(to: outputURL)

        let compiledURL = try MLModel.compileModel(at: outputURL)
        return try MLModel(contentsOf: compiledURL)
    }

    // MARK: - Text Classification Training

    /// Trains a text classifier for intent recognition from user conversations.
    func trainIntentClassifier(
        from conversations: [(text: String, intent: String)],
        config: TrainingConfiguration = .defaultConfig
    ) async throws -> MLModel {
        let sessionId = UUID().uuidString

        var textColumn: [String] = []
        var labelColumn: [String] = []

        for entry in conversations {
            textColumn.append(entry.text)
            labelColumn.append(entry.intent)
        }

        let dataTable = try MLDataTable(dictionary: [
            "text": textColumn,
            "label": labelColumn
        ])

        let (trainingData, validationData) = dataTable.randomSplit(by: config.validationFraction)

        let classifier = try MLTextClassifier(
            trainingData: trainingData,
            textColumn: "text",
            labelColumn: "label"
        )

        let evaluation = classifier.evaluation(on: validationData, textColumn: "text", labelColumn: "label")
        _ = 1.0 - evaluation.classificationError

        let outputURL = modelOutputDirectory.appendingPathComponent("IntentClassifier_\(sessionId).mlmodel")
        try classifier.write(to: outputURL)

        let compiledURL = try MLModel.compileModel(at: outputURL)
        return try MLModel(contentsOf: compiledURL)
    }

    // MARK: - Session Management

    func activeSession(id: String) -> TrainingSession? {
        return activeTrainingSessions[id]
    }

    func cancelSession(id: String) {
        activeTrainingSessions.removeValue(forKey: id)
    }

    // MARK: - Data Table Builders

    private func buildDataTable(from transactions: [(features: [String: Any], label: String)]) throws -> MLDataTable {
        guard let first = transactions.first else {
            throw CreateMLPipelineError.insufficientData
        }

        var columns: [String: [Any]] = [:]
        for key in first.features.keys {
            columns[key] = transactions.map { $0.features[key] ?? 0 }
        }
        columns["label"] = transactions.map { $0.label }

        // Build typed dictionary for MLDataTable
        var typedDict: [String: MLDataValueConvertible] = [:]
        for (key, values) in columns {
            if let doubleValues = values as? [Double] {
                typedDict[key] = doubleValues
            } else if let stringValues = values as? [String] {
                typedDict[key] = stringValues
            } else if let intValues = values as? [Int] {
                typedDict[key] = intValues
            }
        }

        return try MLDataTable(dictionary: typedDict)
    }

    private func buildRegressionDataTable(features: [[String: Double]], targets: [Double]) throws -> MLDataTable {
        guard let first = features.first else {
            throw CreateMLPipelineError.insufficientData
        }

        var columns: [String: [Double]] = [:]
        for key in first.keys {
            columns[key] = features.map { $0[key] ?? 0 }
        }
        columns["price"] = targets

        return try MLDataTable(dictionary: columns)
    }
}

// MARK: - Pipeline Error

enum CreateMLPipelineError: LocalizedError {
    case insufficientData
    case trainingFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .insufficientData: return "Insufficient training data"
        case .trainingFailed(let reason): return "Training failed: \(reason)"
        case .exportFailed(let reason): return "Model export failed: \(reason)"
        }
    }
}
