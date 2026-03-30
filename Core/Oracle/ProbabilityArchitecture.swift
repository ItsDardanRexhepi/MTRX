//
//  ProbabilityArchitecture.swift
//  MTRX — Oracle
//
//  Living probability models that update in real-time.
//  Bayesian probability models for risk assessment and prediction.
//

import Foundation

// MARK: - Probability Model

/// A living probability model that updates with new evidence.
struct ProbabilityModel: Identifiable, Sendable {
    let id: UUID
    let name: String
    let hypothesis: String
    var priorProbability: Double
    var posteriorProbability: Double
    var evidenceCount: Int
    var lastUpdated: Date
    var confidenceInterval: ClosedRange<Double>
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        name: String,
        hypothesis: String,
        priorProbability: Double,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.name = name
        self.hypothesis = hypothesis
        self.priorProbability = priorProbability
        self.posteriorProbability = priorProbability
        self.evidenceCount = 0
        self.lastUpdated = Date()
        self.confidenceInterval = max(0, priorProbability - 0.15)...min(1, priorProbability + 0.15)
        self.metadata = metadata
    }
}

// MARK: - Evidence

/// A piece of evidence that updates a probability model.
struct Evidence: Sendable {
    let source: DataFeed
    let description: String
    let likelihood: Double           // P(evidence | hypothesis true)
    let likelihoodComplement: Double // P(evidence | hypothesis false)
    let weight: Double               // Credibility weight (0.0-1.0)
    let timestamp: Date

    init(
        source: DataFeed,
        description: String,
        likelihood: Double,
        likelihoodComplement: Double,
        weight: Double = 1.0,
        timestamp: Date = Date()
    ) {
        self.source = source
        self.description = description
        self.likelihood = likelihood
        self.likelihoodComplement = likelihoodComplement
        self.weight = weight
        self.timestamp = timestamp
    }
}

// MARK: - Risk Assessment

/// Result of a risk assessment computation.
struct RiskAssessment: Sendable {
    let asset: String
    let riskScore: Double            // 0.0 (safe) to 1.0 (extreme risk)
    let volatilityEstimate: Double
    let drawdownProbability: Double  // P(>10% drawdown in next 7 days)
    let tailRiskProbability: Double  // P(>25% drawdown)
    let confidenceLevel: Double
    let factors: [RiskFactor]
    let timestamp: Date
}

/// A factor contributing to the overall risk assessment.
struct RiskFactor: Sendable {
    let name: String
    let contribution: Double  // How much this factor contributes to total risk
    let direction: RiskDirection
    let description: String

    enum RiskDirection: String, Sendable {
        case increasing
        case decreasing
        case stable
    }
}

// MARK: - Probability Architecture

/// Bayesian probability engine that maintains living probability models.
/// Models update in real-time as new evidence arrives from data feeds.
final class ProbabilityArchitecture {

    // MARK: - Properties

    private var models: [UUID: ProbabilityModel] = [:]
    private var evidenceHistory: [Evidence] = []
    private let maxEvidenceHistory: Int = 10_000
    private let bayesianSmoothingFactor: Double = 0.01

    // MARK: - Model Management

    /// Create a new probability model for a hypothesis.
    /// - Parameters:
    ///   - name: Human-readable model name.
    ///   - hypothesis: The hypothesis being modeled.
    ///   - prior: Initial probability estimate (0.0-1.0).
    /// - Returns: The created model.
    @discardableResult
    func createModel(name: String, hypothesis: String, prior: Double) -> ProbabilityModel {
        let model = ProbabilityModel(
            name: name,
            hypothesis: hypothesis,
            priorProbability: prior
        )
        models[model.id] = model
        return model
    }

    /// Update a model with new evidence using Bayes' theorem.
    /// - Parameters:
    ///   - modelId: The model to update.
    ///   - evidence: The new evidence.
    func updateModel(_ modelId: UUID, with evidence: Evidence) {
        guard var model = models[modelId] else { return }

        // Bayes' theorem: P(H|E) = P(E|H) * P(H) / P(E)
        // where P(E) = P(E|H)*P(H) + P(E|~H)*P(~H)

        let prior = model.posteriorProbability
        let pEgivenH = evidence.likelihood
        let pEgivenNotH = evidence.likelihoodComplement

        // Apply evidence weight
        let weightedLikelihood = pEgivenH * evidence.weight + (1 - evidence.weight) * 0.5
        let weightedComplementLikelihood = pEgivenNotH * evidence.weight + (1 - evidence.weight) * 0.5

        // Compute marginal likelihood P(E)
        let pE = weightedLikelihood * prior + weightedComplementLikelihood * (1 - prior)

        // Apply Laplace smoothing to prevent zero probabilities
        let smoothedPE = pE + bayesianSmoothingFactor

        // Compute posterior
        let posterior = (weightedLikelihood * prior) / smoothedPE
        let clampedPosterior = max(0.001, min(0.999, posterior))

        // Update model
        model.posteriorProbability = clampedPosterior
        model.evidenceCount += 1
        model.lastUpdated = Date()

        // Update confidence interval (narrows with more evidence)
        let intervalWidth = 0.30 / sqrt(Double(model.evidenceCount + 1))
        model.confidenceInterval = max(0, clampedPosterior - intervalWidth)...min(1, clampedPosterior + intervalWidth)

        models[modelId] = model
        evidenceHistory.append(evidence)

        // Prune evidence history
        if evidenceHistory.count > maxEvidenceHistory {
            evidenceHistory.removeFirst(evidenceHistory.count - maxEvidenceHistory)
        }
    }

    // MARK: - Update Cycle

    /// Update all models with latest data from feeds.
    /// Called by Oracle during each analysis cycle.
    /// - Returns: Insights generated from model updates.
    func updateModels() async -> [OracleInsight] {
        var insights: [OracleInsight] = []

        for (id, model) in models {
            // TODO: Fetch relevant evidence from data feeds
            // Update each model with new evidence

            // Check for significant probability shifts
            let shift = abs(model.posteriorProbability - model.priorProbability)
            if shift > 0.15 {
                let direction = model.posteriorProbability > model.priorProbability ? "increased" : "decreased"
                insights.append(OracleInsight(
                    type: .prediction,
                    category: .market,
                    content: "\(model.name): probability \(direction) to \(String(format: "%.1f%%", model.posteriorProbability * 100))",
                    confidence: 1.0 - (model.confidenceInterval.upperBound - model.confidenceInterval.lowerBound),
                    priority: shift > 0.30 ? .high : .normal,
                    metadata: ["model_id": id.uuidString, "shift": String(format: "%.3f", shift)]
                ))
            }
        }

        return insights
    }

    // MARK: - Risk Assessment

    /// Assess risk for a specific asset.
    /// - Parameter asset: The asset identifier.
    /// - Returns: A comprehensive risk assessment.
    func assessRisk(for asset: String) async -> RiskAssessment {
        // TODO: Implement multi-factor risk assessment
        // - Historical volatility
        // - Correlation risk
        // - Liquidity risk
        // - Smart contract risk
        // - Regulatory risk
        // - Concentration risk

        return RiskAssessment(
            asset: asset,
            riskScore: 0.5,
            volatilityEstimate: 0.0,
            drawdownProbability: 0.0,
            tailRiskProbability: 0.0,
            confidenceLevel: 0.5,
            factors: [],
            timestamp: Date()
        )
    }

    // MARK: - Queries

    /// Get a specific model by ID.
    func model(id: UUID) -> ProbabilityModel? {
        models[id]
    }

    /// Get all models, optionally filtered.
    func allModels() -> [ProbabilityModel] {
        Array(models.values).sorted { $0.lastUpdated > $1.lastUpdated }
    }

    /// Get models where posterior has shifted significantly from prior.
    func significantShifts(threshold: Double = 0.15) -> [ProbabilityModel] {
        models.values.filter {
            abs($0.posteriorProbability - $0.priorProbability) > threshold
        }.sorted {
            abs($0.posteriorProbability - $0.priorProbability) > abs($1.posteriorProbability - $1.priorProbability)
        }
    }
}
