// MetalPerformanceShaders.swift
// MTRX Apple Integration — Intelligence
// ML workload acceleration using MetalPerformanceShadersGraph

import MetalPerformanceShadersGraph
import Metal
import Foundation

// MARK: - MPS Graph Accelerator

final class MPSGraphAccelerator {

    // MARK: - Shared Instance

    static let shared = MPSGraphAccelerator()

    // MARK: - Properties

    private let device: MTLDevice
    private let graph: MPSGraph
    private var compiledGraphs: [String: MPSGraphExecutable] = [:]

    // MARK: - Initialization

    private init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        self.graph = MPSGraph()
    }

    // MARK: - Matrix Multiplication

    /// Performs GPU-accelerated matrix multiplication for portfolio optimization.
    func matrixMultiply(
        matrixA: [[Float]],
        matrixB: [[Float]]
    ) throws -> [[Float]] {
        let rowsA = matrixA.count
        let colsA = matrixA.first?.count ?? 0
        let colsB = matrixB.first?.count ?? 0

        guard colsA == matrixB.count else {
            throw MPSAcceleratorError.dimensionMismatch
        }

        let opGraph = MPSGraph()

        let inputA = opGraph.placeholder(
            shape: [NSNumber(value: rowsA), NSNumber(value: colsA)],
            dataType: .float32,
            name: "matrixA"
        )
        let inputB = opGraph.placeholder(
            shape: [NSNumber(value: colsA), NSNumber(value: colsB)],
            dataType: .float32,
            name: "matrixB"
        )

        let result = opGraph.matrixMultiplication(
            primary: inputA,
            secondary: inputB,
            name: "result"
        )

        let flatA = matrixA.flatMap { $0 }
        let flatB = matrixB.flatMap { $0 }

        let dataA = flatA.withUnsafeBufferPointer { Data(buffer: $0) }
        let dataB = flatB.withUnsafeBufferPointer { Data(buffer: $0) }

        let tensorA = MPSGraphTensorData(
            device: MPSGraphDevice(mtlDevice: device),
            data: dataA,
            shape: [NSNumber(value: rowsA), NSNumber(value: colsA)],
            dataType: .float32
        )
        let tensorB = MPSGraphTensorData(
            device: MPSGraphDevice(mtlDevice: device),
            data: dataB,
            shape: [NSNumber(value: colsA), NSNumber(value: colsB)],
            dataType: .float32
        )

        let resultDict = opGraph.run(
            feeds: [inputA: tensorA, inputB: tensorB],
            targetTensors: [result],
            targetOperations: nil
        )

        guard let resultData = resultDict[result] else {
            throw MPSAcceleratorError.executionFailed
        }

        var outputFlat = [Float](repeating: 0, count: rowsA * colsB)
        resultData.mpsndarray().readBytes(&outputFlat, strideBytes: nil)

        var output: [[Float]] = []
        for i in 0..<rowsA {
            output.append(Array(outputFlat[(i * colsB)..<((i + 1) * colsB)]))
        }
        return output
    }

    // MARK: - Neural Network Forward Pass

    /// Builds and executes a simple feedforward network for quick inference.
    func feedForwardInference(
        input: [Float],
        weights: [[Float]],
        biases: [[Float]],
        activations: [ActivationType]
    ) throws -> [Float] {
        let opGraph = MPSGraph()

        var currentTensor = opGraph.placeholder(
            shape: [1, NSNumber(value: input.count)],
            dataType: .float32,
            name: "input"
        )

        var feeds: [MPSGraphTensor: MPSGraphTensorData] = [:]
        let inputData = input.withUnsafeBufferPointer { Data(buffer: $0) }
        feeds[currentTensor] = MPSGraphTensorData(
            device: MPSGraphDevice(mtlDevice: device),
            data: inputData,
            shape: [1, NSNumber(value: input.count)],
            dataType: .float32
        )

        for (index, (layerWeights, layerBiases)) in zip(weights, biases).enumerated() {
            let inputSize = index == 0 ? input.count : weights[index - 1].count / (index == 0 ? input.count : weights[index - 1].count)
            let outputSize = layerBiases.count

            // Create weight constant
            let weightData = layerWeights.withUnsafeBufferPointer { Data(buffer: $0) }
            let weightTensor = opGraph.constant(
                weightData,
                shape: [NSNumber(value: layerWeights.count / outputSize), NSNumber(value: outputSize)],
                dataType: .float32
            )

            // Matrix multiply
            currentTensor = opGraph.matrixMultiplication(
                primary: currentTensor,
                secondary: weightTensor,
                name: "layer_\(index)_mm"
            )

            // Add bias
            let biasData = layerBiases.withUnsafeBufferPointer { Data(buffer: $0) }
            let biasTensor = opGraph.constant(
                biasData,
                shape: [1, NSNumber(value: outputSize)],
                dataType: .float32
            )
            currentTensor = opGraph.addition(currentTensor, biasTensor, name: "layer_\(index)_bias")

            // Activation
            if index < activations.count {
                currentTensor = applyActivation(opGraph, tensor: currentTensor, type: activations[index], name: "layer_\(index)_act")
            }
        }

        let results = opGraph.run(
            feeds: feeds,
            targetTensors: [currentTensor],
            targetOperations: nil
        )

        guard let resultData = results[currentTensor] else {
            throw MPSAcceleratorError.executionFailed
        }

        let outputSize = biases.last?.count ?? 0
        var output = [Float](repeating: 0, count: outputSize)
        resultData.mpsndarray().readBytes(&output, strideBytes: nil)
        return output
    }

    // MARK: - Convolution for Time Series

    /// 1D convolution for time-series pattern detection.
    func convolve1D(
        signal: [Float],
        kernel: [Float],
        stride: Int = 1
    ) throws -> [Float] {
        let opGraph = MPSGraph()
        let signalLength = signal.count
        let kernelLength = kernel.count
        let outputLength = (signalLength - kernelLength) / stride + 1

        let signalTensor = opGraph.placeholder(
            shape: [1, 1, NSNumber(value: signalLength), 1],
            dataType: .float32,
            name: "signal"
        )

        let kernelData = kernel.withUnsafeBufferPointer { Data(buffer: $0) }
        let kernelTensor = opGraph.constant(
            kernelData,
            shape: [1, 1, NSNumber(value: kernelLength), 1],
            dataType: .float32
        )

        let descriptor = MPSGraphConvolution2DOpDescriptor(
            strideInX: stride, strideInY: 1,
            dilationRateInX: 1, dilationRateInY: 1,
            groups: 1,
            paddingStyle: .TF_VALID,
            dataLayout: .NHWC,
            weightsLayout: .HWIO
        )!

        let result = opGraph.convolution2D(signalTensor, weights: kernelTensor, descriptor: descriptor, name: "conv1d")

        let signalData = signal.withUnsafeBufferPointer { Data(buffer: $0) }
        let feeds: [MPSGraphTensor: MPSGraphTensorData] = [
            signalTensor: MPSGraphTensorData(
                device: MPSGraphDevice(mtlDevice: device),
                data: signalData,
                shape: [1, 1, NSNumber(value: signalLength), 1],
                dataType: .float32
            )
        ]

        let results = opGraph.run(feeds: feeds, targetTensors: [result], targetOperations: nil)

        guard let resultData = results[result] else {
            throw MPSAcceleratorError.executionFailed
        }

        var output = [Float](repeating: 0, count: outputLength)
        resultData.mpsndarray().readBytes(&output, strideBytes: nil)
        return output
    }

    // MARK: - Activation Functions

    enum ActivationType {
        case relu
        case sigmoid
        case tanh
        case softmax
    }

    private func applyActivation(_ graph: MPSGraph, tensor: MPSGraphTensor, type: ActivationType, name: String) -> MPSGraphTensor {
        switch type {
        case .relu:
            return graph.reLU(with: tensor, name: name)
        case .sigmoid:
            return graph.sigmoid(with: tensor, name: name)
        case .tanh:
            return graph.tanh(with: tensor, name: name)
        case .softmax:
            return graph.softMax(with: tensor, axis: -1, name: name)
        }
    }
}

// MARK: - MPS Accelerator Error

enum MPSAcceleratorError: LocalizedError {
    case dimensionMismatch
    case executionFailed
    case graphCompilationFailed

    var errorDescription: String? {
        switch self {
        case .dimensionMismatch: return "Matrix dimensions do not match"
        case .executionFailed: return "MPS graph execution failed"
        case .graphCompilationFailed: return "Failed to compile MPS graph"
        }
    }
}
