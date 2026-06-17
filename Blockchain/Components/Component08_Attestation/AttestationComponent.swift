// AttestationComponent.swift
// MTRX Blockchain - Components - Attestation
//
// User-facing attestation creation and verification workflows

import Foundation

// MARK: - Protocols

protocol AttestationComponentDelegate: AnyObject {
    func attestationComponent(_ component: AttestationComponent, didCreate attestationId: String)
    func attestationComponent(_ component: AttestationComponent, didVerify attestationId: String, isValid: Bool)
    func attestationComponent(_ component: AttestationComponent, didFailWithError error: AttestationComponentError)
}

// MARK: - Data Models

enum AttestationCategory: String, Codable {
    case identity, credential, agreement, ownership, reputation, certification, custom
}

struct AttestationWorkflow {
    let workflowId: String
    let category: AttestationCategory
    let steps: [WorkflowStep]
    let requiredFields: [String]
    let autoVerify: Bool
}

struct WorkflowStep {
    let stepId: String
    let name: String
    let description: String
    let isCompleted: Bool
    let requiresUserInput: Bool
}

struct UserAttestation {
    let attestationId: String
    let category: AttestationCategory
    let subject: String
    let claim: String
    let evidence: [String: String]
    let onChainUID: String?
    let proofURL: URL?
    let status: UserAttestationStatus
    let createdAt: Date
}

enum UserAttestationStatus: String {
    case draft, pending, confirmed, verified, rejected, expired
}

enum AttestationComponentError: Error, LocalizedError {
    case workflowNotFound
    case missingRequiredField(field: String)
    case verificationFailed
    case attestationExpired
    case invalidEvidence
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .workflowNotFound: return "Attestation workflow not found."
        case .missingRequiredField(let f): return "Missing required field: \(f)"
        case .verificationFailed: return "Attestation verification failed."
        case .attestationExpired: return "Attestation has expired."
        case .invalidEvidence: return "Evidence provided is invalid."
        case .notConfigured: return "Attestation contract not configured (PendingCredentials.Components.attestation)."
        }
    }
}

// MARK: - AttestationComponent

final class AttestationComponent {

    // MARK: - Properties

    weak var delegate: AttestationComponentDelegate?

    private let easManager: EASManager
    private let proofGenerator: ProofGenerator
    private let attestationQueue: AttestationQueue
    private var workflows: [String: AttestationWorkflow] = [:]
    private var userAttestations: [String: UserAttestation] = [:]
    private let processingQueue = DispatchQueue(label: "com.mtrx.attestation.component", qos: .userInitiated)

    // MARK: - Initialization

    init(easManager: EASManager, proofGenerator: ProofGenerator, attestationQueue: AttestationQueue) {
        self.easManager = easManager
        self.proofGenerator = proofGenerator
        self.attestationQueue = attestationQueue
        registerDefaultWorkflows()
    }

    // MARK: - Workflow Management

    /// Get a workflow for an attestation category
    func getWorkflow(for category: AttestationCategory) -> AttestationWorkflow? {
        return workflows.values.first { $0.category == category }
    }

    /// Register a custom workflow
    func registerWorkflow(_ workflow: AttestationWorkflow) {
        workflows[workflow.workflowId] = workflow
    }

    // MARK: - Attestation Creation

    /// Create a new attestation through the user workflow
    func createAttestation(category: AttestationCategory, subject: String, claim: String, evidence: [String: String], completion: @escaping (Result<UserAttestation, AttestationComponentError>) -> Void) {
        guard let workflow = getWorkflow(for: category) else {
            completion(.failure(.workflowNotFound))
            return
        }
        // Validate required fields
        for field in workflow.requiredFields {
            guard evidence[field] != nil else {
                completion(.failure(.missingRequiredField(field: field)))
                return
            }
        }

        let attestation = UserAttestation(
            attestationId: UUID().uuidString, category: category, subject: subject,
            claim: claim, evidence: evidence, onChainUID: nil, proofURL: nil,
            status: .pending, createdAt: Date()
        )
        userAttestations[attestation.attestationId] = attestation

        // Queue for on-chain submission
        let request = AttestationRequest(
            schemaUID: "", recipient: subject, expirationTime: nil,
            revocable: true, data: Data(), value: 0
        )
        let metadata = ["category": category.rawValue]
        attestationQueue.enqueue(request: request, metadata: metadata) { [weak self] result in
            switch result {
            case .success:
                self?.delegate?.attestationComponent(self!, didCreate: attestation.attestationId)
                completion(.success(attestation))
            case .failure:
                completion(.failure(.verificationFailed))
            }
        }
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `attest(bytes32 schemaUID, address recipient, bytes data)`.
    /// ASSUMPTION: the deployed attestation contract exposes this selector
    /// (EAS-style attest). Adjust the signature if the deployed ABI differs.
    static func encodeAttest(schemaUID: Data, recipient: String, data: Data) -> Data {
        var schemaWord = Data(repeating: 0, count: 32)
        let head = schemaUID.prefix(32)
        schemaWord.replaceSubrange(0..<head.count, with: head) // left-aligned bytes32
        var out = ABIEncoder.functionSelector("attest(bytes32,address,bytes)")
        out.append(schemaWord)
        out.append(ABIEncoder.encodeAddress(recipient))
        out.append(ABIEncoder.encodeOffset(96)) // bytes arg follows 3 head words
        out.append(ABIEncoder.encodeBytes(data))
        return out
    }

    /// Create an attestation on-chain through the real submit pipeline:
    /// enclave-signed UserOp → server paymaster → bundler. The contract address
    /// is deferred to PendingCredentials (nil until set → throws, never faked).
    /// Static: the money path needs no instance state, so it stays testable
    /// without constructing the full EAS/proof/queue graph.
    @MainActor
    static func createAttestationOnChain(
        schemaUID: Data,
        recipient: String,
        data: Data,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.attestation)
    ) async throws -> WalletTransactionService.Submission {
        guard let attestationContract = contract else { throw AttestationComponentError.notConfigured }
        return try await service.submitCall(
            to: attestationContract,
            value: 0,
            data: encodeAttest(schemaUID: schemaUID, recipient: recipient, data: data),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Verification

    /// Verify an attestation
    func verifyAttestation(attestationId: String, completion: @escaping (Result<Bool, AttestationComponentError>) -> Void) {
        guard let attestation = userAttestations[attestationId] else {
            completion(.failure(.verificationFailed))
            return
        }
        guard let uid = attestation.onChainUID else {
            completion(.failure(.verificationFailed))
            return
        }
        easManager.verifyAttestation(uid: uid) { [weak self] result in
            let isValid = (try? result.get()) != nil
            self?.delegate?.attestationComponent(self!, didVerify: attestationId, isValid: isValid)
            completion(.success(isValid))
        }
    }

    /// Generate a proof document for an attestation
    func generateProof(attestationId: String, completion: @escaping (Result<URL, AttestationComponentError>) -> Void) {
        guard let attestation = userAttestations[attestationId], let uid = attestation.onChainUID else {
            completion(.failure(.verificationFailed))
            return
        }
        let proofType: ProofType = {
            switch attestation.category {
            case .identity: return .identity
            case .credential: return .credential
            case .ownership: return .ownership
            case .agreement: return .agreement
            default: return .certification
            }
        }()
        proofGenerator.generateProof(attestationUID: uid, proofType: proofType) { result in
            switch result {
            case .success(let proof): completion(.success(proof.verificationURL))
            case .failure: completion(.failure(.verificationFailed))
            }
        }
    }

    // MARK: - Query

    func getUserAttestations(subject: String) -> [UserAttestation] {
        return userAttestations.values.filter { $0.subject == subject }
    }

    func getAttestation(id: String) -> UserAttestation? {
        return userAttestations[id]
    }

    // MARK: - Private

    private func registerDefaultWorkflows() {
        let identityWorkflow = AttestationWorkflow(
            workflowId: "identity_default", category: .identity,
            steps: [
                WorkflowStep(stepId: "1", name: "Provide Identity", description: "Enter identity details", isCompleted: false, requiresUserInput: true),
                WorkflowStep(stepId: "2", name: "Submit Proof", description: "Upload supporting evidence", isCompleted: false, requiresUserInput: true),
                WorkflowStep(stepId: "3", name: "On-chain Attestation", description: "Record on Base", isCompleted: false, requiresUserInput: false)
            ],
            requiredFields: ["name", "identifier"],
            autoVerify: false
        )
        workflows[identityWorkflow.workflowId] = identityWorkflow
    }
}
