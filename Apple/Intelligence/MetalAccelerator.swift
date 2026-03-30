// MetalAccelerator.swift
// MTRX Apple Integration — Intelligence
// GPU acceleration via Metal for financial calculations

import Metal
import MetalKit
import Foundation

// MARK: - Metal Accelerator

final class MetalAccelerator {

    // MARK: - Shared Instance

    static let shared = MetalAccelerator()

    // MARK: - Properties

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var computePipelines: [String: MTLComputePipelineState] = [:]
    private let pipelineQueue = DispatchQueue(label: "com.mtrx.metal", qos: .userInitiated)

    // MARK: - Compute Kernels

    enum ComputeKernel: String {
        case portfolioValuation = "portfolio_valuation"
        case riskCalculation = "risk_calculation"
        case monteCarloSimulation = "monte_carlo_simulation"
        case blackScholes = "black_scholes"
        case yieldOptimization = "yield_optimization"
        case correlationMatrix = "correlation_matrix"
        case movingAverage = "moving_average"
        case volatilityEstimation = "volatility_estimation"
    }

    // MARK: - Initialization

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = commandQueue
    }

    // MARK: - Pipeline Setup

    /// Compiles a compute kernel and caches the pipeline state.
    func compilePipeline(for kernel: ComputeKernel) throws {
        guard let library = device.makeDefaultLibrary() else {
            throw MetalError.libraryNotFound
        }

        guard let function = library.makeFunction(name: kernel.rawValue) else {
            throw MetalError.functionNotFound(kernel.rawValue)
        }

        let pipelineState = try device.makeComputePipelineState(function: function)
        computePipelines[kernel.rawValue] = pipelineState
    }

    // MARK: - Portfolio Valuation (GPU)

    /// Calculates portfolio valuation across all positions in parallel.
    func computePortfolioValuation(
        balances: [Float],
        prices: [Float],
        weights: [Float]
    ) throws -> [Float] {
        let count = balances.count
        guard count == prices.count, count == weights.count else {
            throw MetalError.bufferSizeMismatch
        }

        let balanceBuffer = try makeBuffer(from: balances)
        let priceBuffer = try makeBuffer(from: prices)
        let weightBuffer = try makeBuffer(from: weights)
        let resultBuffer = try makeBuffer(count: count)

        try dispatch(
            kernel: .portfolioValuation,
            buffers: [balanceBuffer, priceBuffer, weightBuffer, resultBuffer],
            count: count
        )

        return extractResults(from: resultBuffer, count: count)
    }

    // MARK: - Monte Carlo Simulation (GPU)

    /// Runs Monte Carlo simulation for risk assessment on GPU.
    func runMonteCarloSimulation(
        initialPrice: Float,
        volatility: Float,
        drift: Float,
        timeSteps: Int,
        simulations: Int
    ) throws -> MonteCarloResult {
        let paramCount = 4
        let params: [Float] = [initialPrice, volatility, drift, Float(timeSteps)]
        let paramsBuffer = try makeBuffer(from: params)
        let resultCount = simulations * timeSteps
        let resultBuffer = try makeBuffer(count: resultCount)

        try dispatch(
            kernel: .monteCarloSimulation,
            buffers: [paramsBuffer, resultBuffer],
            count: simulations
        )

        let allPaths = extractResults(from: resultBuffer, count: resultCount)

        // Compute statistics
        let finalPrices = stride(from: timeSteps - 1, to: resultCount, by: timeSteps).map { allPaths[$0] }
        let meanPrice = finalPrices.reduce(0, +) / Float(simulations)
        let variance = finalPrices.map { pow($0 - meanPrice, 2) }.reduce(0, +) / Float(simulations)
        let sortedPrices = finalPrices.sorted()
        let var95Index = Int(Float(simulations) * 0.05)
        let valueAtRisk95 = sortedPrices[var95Index]

        return MonteCarloResult(
            meanFinalPrice: meanPrice,
            standardDeviation: sqrt(variance),
            valueAtRisk95: valueAtRisk95,
            simulationCount: simulations,
            timeSteps: timeSteps
        )
    }

    // MARK: - Correlation Matrix (GPU)

    /// Computes correlation matrix for asset returns on GPU.
    func computeCorrelationMatrix(
        returnSeries: [[Float]],
        assetCount: Int
    ) throws -> [[Float]] {
        let seriesLength = returnSeries.first?.count ?? 0
        let flatReturns = returnSeries.flatMap { $0 }
        let inputBuffer = try makeBuffer(from: flatReturns)
        let resultCount = assetCount * assetCount
        let resultBuffer = try makeBuffer(count: resultCount)

        try dispatch(
            kernel: .correlationMatrix,
            buffers: [inputBuffer, resultBuffer],
            count: resultCount
        )

        let flatResult = extractResults(from: resultBuffer, count: resultCount)
        var matrix: [[Float]] = []
        for i in 0..<assetCount {
            let row = Array(flatResult[(i * assetCount)..<((i + 1) * assetCount)])
            matrix.append(row)
        }
        return matrix
    }

    // MARK: - Buffer Management

    private func makeBuffer(from data: [Float]) throws -> MTLBuffer {
        let byteLength = data.count * MemoryLayout<Float>.stride
        guard let buffer = device.makeBuffer(bytes: data, length: byteLength, options: .storageModeShared) else {
            throw MetalError.bufferCreationFailed
        }
        return buffer
    }

    private func makeBuffer(count: Int) throws -> MTLBuffer {
        let byteLength = count * MemoryLayout<Float>.stride
        guard let buffer = device.makeBuffer(length: byteLength, options: .storageModeShared) else {
            throw MetalError.bufferCreationFailed
        }
        return buffer
    }

    private func extractResults(from buffer: MTLBuffer, count: Int) -> [Float] {
        let pointer = buffer.contents().bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }

    // MARK: - Dispatch

    private func dispatch(kernel: ComputeKernel, buffers: [MTLBuffer], count: Int) throws {
        guard let pipelineState = computePipelines[kernel.rawValue] else {
            try compilePipeline(for: kernel)
            guard let pipeline = computePipelines[kernel.rawValue] else {
                throw MetalError.pipelineNotFound(kernel.rawValue)
            }
            try dispatchWithPipeline(pipeline, buffers: buffers, count: count)
            return
        }
        try dispatchWithPipeline(pipelineState, buffers: buffers, count: count)
    }

    private func dispatchWithPipeline(_ pipeline: MTLComputePipelineState, buffers: [MTLBuffer], count: Int) throws {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalError.encoderCreationFailed
        }

        encoder.setComputePipelineState(pipeline)
        for (index, buffer) in buffers.enumerated() {
            encoder.setBuffer(buffer, offset: 0, index: index)
        }

        let threadGroupSize = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, count), height: 1, depth: 1)
        let threadGroups = MTLSize(width: (count + threadGroupSize.width - 1) / threadGroupSize.width, height: 1, depth: 1)
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw MetalError.executionFailed(error.localizedDescription)
        }
    }

    // MARK: - Device Info

    var deviceName: String { device.name }
    var maxThreadsPerGroup: Int { device.maxThreadsPerThreadgroup.width }
    var hasUnifiedMemory: Bool { device.hasUnifiedMemory }
}

// MARK: - Monte Carlo Result

struct MonteCarloResult {
    let meanFinalPrice: Float
    let standardDeviation: Float
    let valueAtRisk95: Float
    let simulationCount: Int
    let timeSteps: Int
}

// MARK: - Metal Error

enum MetalError: LocalizedError {
    case libraryNotFound
    case functionNotFound(String)
    case pipelineNotFound(String)
    case bufferCreationFailed
    case bufferSizeMismatch
    case encoderCreationFailed
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .libraryNotFound: return "Metal default library not found"
        case .functionNotFound(let name): return "Metal function '\(name)' not found"
        case .pipelineNotFound(let name): return "Pipeline '\(name)' not compiled"
        case .bufferCreationFailed: return "Failed to create Metal buffer"
        case .bufferSizeMismatch: return "Input buffer sizes do not match"
        case .encoderCreationFailed: return "Failed to create compute encoder"
        case .executionFailed(let reason): return "Metal execution failed: \(reason)"
        }
    }
}
