// AttestationQueue.swift
// MTRX Blockchain - Attestation
//
// Batch vs immediate attestation classification and queue management

import Foundation

// MARK: - Protocols

protocol AttestationQueueDelegate: AnyObject {
    func queue(_ queue: AttestationQueue, didProcessBatch batchId: String, count: Int)
    func queue(_ queue: AttestationQueue, didProcessImmediate attestationId: String)
    func queue(_ queue: AttestationQueue, didFailWithError error: AttestationQueueError)
}

// MARK: - Data Models

enum AttestationPriority: Int, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    static func < (lhs: AttestationPriority, rhs: AttestationPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

enum ProcessingMode {
    case immediate
    case batched
}

struct QueuedAttestation {
    let id: String
    let request: AttestationRequest
    let priority: AttestationPriority
    let processingMode: ProcessingMode
    let enqueuedAt: Date
    let deadline: Date?
    let metadata: [String: String]
}

struct BatchResult {
    let batchId: String
    let attestationUIDs: [String]
    let totalGasUsed: UInt64
    let gasSavedVsIndividual: UInt64
    let processedAt: Date
}

struct QueueStatistics {
    let pendingCount: Int
    let batchedCount: Int
    let immediateCount: Int
    let processedToday: Int
    let averageBatchSize: Double
    let averageProcessingTime: TimeInterval
}

enum AttestationQueueError: Error, LocalizedError {
    case queueFull
    case deadlineExpired(attestationId: String)
    case batchSubmissionFailed(reason: String)
    case classificationFailed
    case duplicateAttestation(id: String)

    var errorDescription: String? {
        switch self {
        case .queueFull: return "Attestation queue is at maximum capacity."
        case .deadlineExpired(let id): return "Deadline expired for attestation: \(id)"
        case .batchSubmissionFailed(let reason): return "Batch submission failed: \(reason)"
        case .classificationFailed: return "Failed to classify attestation priority."
        case .duplicateAttestation(let id): return "Duplicate attestation: \(id)"
        }
    }
}

// MARK: - Classification Rules

struct ClassificationRule {
    let name: String
    let condition: (AttestationRequest, [String: String]) -> Bool
    let assignedMode: ProcessingMode
    let assignedPriority: AttestationPriority
}

// MARK: - AttestationQueue

final class AttestationQueue {

    // MARK: - Configuration

    struct Configuration {
        let maxQueueSize: Int
        let maxBatchSize: Int
        let batchIntervalSeconds: TimeInterval
        let immediateGasThreshold: UInt64
        let batchGasThreshold: UInt64

        static let `default` = Configuration(
            maxQueueSize: 1000,
            maxBatchSize: 50,
            batchIntervalSeconds: 300,
            immediateGasThreshold: 200_000,
            batchGasThreshold: 5_000_000
        )
    }

    // MARK: - Properties

    weak var delegate: AttestationQueueDelegate?

    private let configuration: Configuration
    private let easManager: EASManager

    /// Pending attestations awaiting processing
    private var pendingQueue: [QueuedAttestation] = []

    /// Batch accumulator
    private var batchAccumulator: [QueuedAttestation] = []

    /// Immediate processing queue
    private var immediateQueue: [QueuedAttestation] = []

    /// Classification rules
    private var classificationRules: [ClassificationRule] = []

    /// Processing statistics
    private var processedCount: Int = 0
    private var totalBatches: Int = 0
    private var totalGasSaved: UInt64 = 0

    /// Batch timer
    private var batchTimer: Timer?

    /// Active batch IDs
    private var activeBatchIds: Set<String> = []

    private let queueLock = NSLock()
    private let processingQueue = DispatchQueue(label: "com.mtrx.attestation.queue", qos: .userInitiated)

    // MARK: - Initialization

    init(configuration: Configuration = .default, easManager: EASManager) {
        self.configuration = configuration
        self.easManager = easManager
        setupDefaultRules()
    }

    // MARK: - Queue Operations

    /// Enqueue an attestation for processing
    func enqueue(
        request: AttestationRequest,
        metadata: [String: String] = [:],
        deadline: Date? = nil,
        completion: @escaping (Result<String, AttestationQueueError>) -> Void
    ) {
        queueLock.lock()
        defer { queueLock.unlock() }

        guard pendingQueue.count < configuration.maxQueueSize else {
            completion(.failure(.queueFull))
            return
        }

        let id = UUID().uuidString

        // Classify the attestation
        let (mode, priority) = classify(request: request, metadata: metadata)

        let queued = QueuedAttestation(
            id: id,
            request: request,
            priority: priority,
            processingMode: mode,
            enqueuedAt: Date(),
            deadline: deadline,
            metadata: metadata
        )

        switch mode {
        case .immediate:
            immediateQueue.append(queued)
            processImmediate(queued)
        case .batched:
            batchAccumulator.append(queued)
            checkBatchThreshold()
        }

        pendingQueue.append(queued)
        completion(.success(id))
    }

    /// Force process all pending batched attestations
    func flushBatch(completion: @escaping (Result<BatchResult, AttestationQueueError>) -> Void) {
        queueLock.lock()
        let batch = batchAccumulator
        batchAccumulator.removeAll()
        queueLock.unlock()

        guard !batch.isEmpty else {
            completion(.success(BatchResult(
                batchId: UUID().uuidString,
                attestationUIDs: [],
                totalGasUsed: 0,
                gasSavedVsIndividual: 0,
                processedAt: Date()
            )))
            return
        }

        processBatch(batch, completion: completion)
    }

    /// Remove an attestation from the queue before processing
    func dequeue(attestationId: String) -> Bool {
        queueLock.lock()
        defer { queueLock.unlock() }

        if let index = pendingQueue.firstIndex(where: { $0.id == attestationId }) {
            pendingQueue.remove(at: index)
            batchAccumulator.removeAll { $0.id == attestationId }
            immediateQueue.removeAll { $0.id == attestationId }
            return true
        }
        return false
    }

    // MARK: - Classification

    /// Classify an attestation request as immediate or batched
    func classify(request: AttestationRequest, metadata: [String: String]) -> (ProcessingMode, AttestationPriority) {
        // Check custom rules first
        for rule in classificationRules {
            if rule.condition(request, metadata) {
                return (rule.assignedMode, rule.assignedPriority)
            }
        }

        // Default classification heuristics
        return defaultClassification(request: request, metadata: metadata)
    }

    /// Add a custom classification rule
    func addClassificationRule(_ rule: ClassificationRule) {
        classificationRules.append(rule)
    }

    // MARK: - Timer Management

    /// Start the batch processing timer
    func startBatchTimer() {
        batchTimer?.invalidate()
        batchTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.batchIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            self?.flushBatch { _ in }
        }
    }

    /// Stop the batch processing timer
    func stopBatchTimer() {
        batchTimer?.invalidate()
        batchTimer = nil
    }

    // MARK: - Statistics

    /// Get current queue statistics
    func getStatistics() -> QueueStatistics {
        queueLock.lock()
        defer { queueLock.unlock() }

        return QueueStatistics(
            pendingCount: pendingQueue.count,
            batchedCount: batchAccumulator.count,
            immediateCount: immediateQueue.count,
            processedToday: processedCount,
            averageBatchSize: totalBatches > 0 ? Double(processedCount) / Double(totalBatches) : 0,
            averageProcessingTime: 0
        )
    }

    // MARK: - Private Implementation

    private func setupDefaultRules() {
        // High-value attestations go immediate
        let highValueRule = ClassificationRule(
            name: "high_value",
            condition: { request, metadata in
                return metadata["category"] == "financial" || metadata["category"] == "legal"
            },
            assignedMode: .immediate,
            assignedPriority: .high
        )

        // Time-sensitive attestations go immediate
        let timeSensitiveRule = ClassificationRule(
            name: "time_sensitive",
            condition: { request, metadata in
                return metadata["time_sensitive"] == "true"
            },
            assignedMode: .immediate,
            assignedPriority: .critical
        )

        // Identity attestations go immediate
        let identityRule = ClassificationRule(
            name: "identity",
            condition: { request, metadata in
                return metadata["category"] == "identity"
            },
            assignedMode: .immediate,
            assignedPriority: .high
        )

        // Social/reputation attestations can be batched
        let socialRule = ClassificationRule(
            name: "social",
            condition: { request, metadata in
                return metadata["category"] == "social" || metadata["category"] == "reputation"
            },
            assignedMode: .batched,
            assignedPriority: .normal
        )

        classificationRules = [highValueRule, timeSensitiveRule, identityRule, socialRule]
    }

    private func defaultClassification(request: AttestationRequest, metadata: [String: String]) -> (ProcessingMode, AttestationPriority) {
        // If the request has a near deadline, process immediately
        if let expiration = request.expirationTime,
           expiration.timeIntervalSinceNow < 3600 {
            return (.immediate, .high)
        }

        // Default to batched with normal priority
        return (.batched, .normal)
    }

    private func processImmediate(_ attestation: QueuedAttestation) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            self.easManager.createAttestation(request: attestation.request) { result in
                switch result {
                case .success:
                    self.processedCount += 1
                    self.removePending(id: attestation.id)
                    self.delegate?.queue(self, didProcessImmediate: attestation.id)
                case .failure:
                    self.delegate?.queue(self, didFailWithError: .batchSubmissionFailed(reason: "Immediate processing failed"))
                }
            }
        }
    }

    private func processBatch(_ batch: [QueuedAttestation], completion: @escaping (Result<BatchResult, AttestationQueueError>) -> Void) {
        let batchId = UUID().uuidString
        activeBatchIds.insert(batchId)

        processingQueue.async { [weak self] in
            guard let self = self else { return }

            let requests = batch.map { $0.request }

            self.easManager.createBatchAttestations(requests: requests) { result in
                switch result {
                case .success(let uids):
                    let batchResult = BatchResult(
                        batchId: batchId,
                        attestationUIDs: uids,
                        totalGasUsed: 0,
                        gasSavedVsIndividual: 0,
                        processedAt: Date()
                    )
                    self.processedCount += batch.count
                    self.totalBatches += 1
                    batch.forEach { self.removePending(id: $0.id) }
                    self.activeBatchIds.remove(batchId)
                    self.delegate?.queue(self, didProcessBatch: batchId, count: batch.count)
                    completion(.success(batchResult))
                case .failure:
                    self.activeBatchIds.remove(batchId)
                    let error = AttestationQueueError.batchSubmissionFailed(reason: "EAS batch call failed")
                    self.delegate?.queue(self, didFailWithError: error)
                    completion(.failure(error))
                }
            }
        }
    }

    private func checkBatchThreshold() {
        if batchAccumulator.count >= configuration.maxBatchSize {
            flushBatch { _ in }
        }
    }

    private func removePending(id: String) {
        queueLock.lock()
        pendingQueue.removeAll { $0.id == id }
        queueLock.unlock()
    }
}
