// ProofGenerator.swift
// MTRX Blockchain - Attestation
//
// Plain language proof generation from on-chain attestations

import Foundation

// MARK: - Protocols

protocol ProofGeneratorDelegate: AnyObject {
    func proofGenerator(_ generator: ProofGenerator, didGenerateProof proof: VerifiableProof)
    func proofGenerator(_ generator: ProofGenerator, didFailWithError error: ProofGenerationError)
}

protocol ProofFormatter {
    func format(attestation: AttestationData, schema: EASSchema, template: ProofTemplate) -> String
}

// MARK: - Data Models

struct VerifiableProof {
    let proofId: String
    let attestationUID: String
    let humanReadableText: String
    let verificationURL: URL
    let qrCodeData: Data?
    let generatedAt: Date
    let expiresAt: Date?
    let issuer: String
    let recipient: String
    let proofType: ProofType
    let metadata: ProofMetadata
}

struct ProofMetadata {
    let schemaName: String
    let chainId: UInt64
    let blockNumber: UInt64
    let transactionHash: String
    let attestationTimestamp: Date
}

enum ProofType: String, Codable {
    case identity = "identity"
    case credential = "credential"
    case ownership = "ownership"
    case agreement = "agreement"
    case certification = "certification"
    case membership = "membership"
    case reputation = "reputation"
}

struct ProofTemplate {
    let templateId: String
    let proofType: ProofType
    let titlePattern: String
    let bodyPattern: String
    let footerPattern: String
    let includeQRCode: Bool
    let includeTimestamp: Bool
}

struct ProofLink {
    let url: URL
    let shortCode: String
    let createdAt: Date
    let accessCount: Int
    let isActive: Bool
}

enum ProofGenerationError: Error, LocalizedError {
    case attestationNotFound
    case schemaNotFound
    case templateNotFound(proofType: ProofType)
    case formattingFailed
    case linkGenerationFailed
    case qrCodeGenerationFailed
    case invalidAttestationData

    var errorDescription: String? {
        switch self {
        case .attestationNotFound: return "Source attestation not found."
        case .schemaNotFound: return "Attestation schema not found."
        case .templateNotFound(let type): return "No proof template for type: \(type.rawValue)"
        case .formattingFailed: return "Failed to format proof document."
        case .linkGenerationFailed: return "Failed to generate verification link."
        case .qrCodeGenerationFailed: return "Failed to generate QR code."
        case .invalidAttestationData: return "Attestation data is invalid or corrupted."
        }
    }
}

// MARK: - ProofGenerator

final class ProofGenerator {

    // MARK: - Properties

    weak var delegate: ProofGeneratorDelegate?

    /// Base URL for verification links
    let verificationBaseURL: URL

    /// EAS manager for attestation retrieval
    private let easManager: EASManager

    /// Registered proof templates
    private var templates: [ProofType: ProofTemplate] = [:]

    /// Generated proof link cache
    private var proofLinks: [String: ProofLink] = [:]

    /// Custom proof formatter
    private var customFormatter: ProofFormatter?

    private let generationQueue = DispatchQueue(label: "com.mtrx.proof.generator", qos: .userInitiated)

    // MARK: - Initialization

    init(
        easManager: EASManager,
        verificationBaseURL: URL = URL(string: "https://mtrx.app/verify")!
    ) {
        self.easManager = easManager
        self.verificationBaseURL = verificationBaseURL
        registerDefaultTemplates()
    }

    // MARK: - Proof Generation

    /// Generate a human-readable proof from an on-chain attestation
    func generateProof(
        attestationUID: String,
        proofType: ProofType,
        completion: @escaping (Result<VerifiableProof, ProofGenerationError>) -> Void
    ) {
        generationQueue.async { [weak self] in
            guard let self = self else { return }

            // Fetch and verify the attestation
            self.easManager.verifyAttestation(uid: attestationUID) { result in
                switch result {
                case .failure:
                    completion(.failure(.attestationNotFound))
                case .success(let attestation):
                    // Get the schema
                    self.easManager.getSchema(uid: attestation.schemaUID) { schemaResult in
                        switch schemaResult {
                        case .failure:
                            completion(.failure(.schemaNotFound))
                        case .success(let schema):
                            self.buildProof(
                                attestation: attestation,
                                schema: schema,
                                proofType: proofType,
                                completion: completion
                            )
                        }
                    }
                }
            }
        }
    }

    /// Generate a batch of proofs for multiple attestations
    func generateBatchProofs(
        attestationUIDs: [String],
        proofType: ProofType,
        completion: @escaping (Result<[VerifiableProof], ProofGenerationError>) -> Void
    ) {
        let group = DispatchGroup()
        var proofs: [VerifiableProof] = []
        var firstError: ProofGenerationError?

        for uid in attestationUIDs {
            group.enter()
            generateProof(attestationUID: uid, proofType: proofType) { result in
                switch result {
                case .success(let proof):
                    proofs.append(proof)
                case .failure(let error):
                    if firstError == nil { firstError = error }
                }
                group.leave()
            }
        }

        group.notify(queue: generationQueue) {
            if let error = firstError, proofs.isEmpty {
                completion(.failure(error))
            } else {
                completion(.success(proofs))
            }
        }
    }

    // MARK: - Verification Links

    /// Generate a shareable verification link for a proof
    func generateVerificationLink(for proof: VerifiableProof) -> Result<ProofLink, ProofGenerationError> {
        let shortCode = generateShortCode(for: proof.proofId)
        let url = verificationBaseURL.appendingPathComponent(shortCode)

        let link = ProofLink(
            url: url,
            shortCode: shortCode,
            createdAt: Date(),
            accessCount: 0,
            isActive: true
        )

        proofLinks[shortCode] = link
        return .success(link)
    }

    /// Resolve a verification link to a proof
    func resolveVerificationLink(shortCode: String) -> ProofLink? {
        return proofLinks[shortCode]
    }

    // MARK: - Template Management

    /// Register a custom proof template
    func registerTemplate(_ template: ProofTemplate) {
        templates[template.proofType] = template
    }

    /// Set a custom proof formatter
    func setFormatter(_ formatter: ProofFormatter) {
        self.customFormatter = formatter
    }

    // MARK: - Plain Language Conversion

    /// Convert attestation data into plain language description
    func convertToPlainLanguage(attestation: AttestationData, schema: EASSchema) -> String {
        let decodedFields = decodeAttestationData(attestation.data, schema: schema)

        var components: [String] = []
        components.append("This attestation confirms that:")
        components.append("")

        for (key, value) in decodedFields {
            let description = fieldToPlainLanguage(fieldName: key, value: value)
            components.append("  - \(description)")
        }

        components.append("")
        components.append("Issued by: \(formatAddress(attestation.attester))")
        components.append("Issued to: \(formatAddress(attestation.recipient))")
        components.append("Date: \(formatDate(attestation.time))")

        if let expiration = attestation.expirationTime {
            components.append("Valid until: \(formatDate(expiration))")
        } else {
            components.append("No expiration")
        }

        return components.joined(separator: "\n")
    }

    // MARK: - QR Code Generation

    /// Generate a QR code for proof verification
    func generateQRCode(for verificationURL: URL) -> Data? {
        // TODO: Generate QR code image data using CoreImage CIFilter
        // CIFilter(name: "CIQRCodeGenerator")
        return nil
    }

    // MARK: - Private Implementation

    private func registerDefaultTemplates() {
        let identityTemplate = ProofTemplate(
            templateId: "identity_default",
            proofType: .identity,
            titlePattern: "Identity Verification Proof",
            bodyPattern: "This document certifies that the identity of {recipient} has been verified on the Base blockchain.",
            footerPattern: "Verify at: {verification_url}",
            includeQRCode: true,
            includeTimestamp: true
        )

        let credentialTemplate = ProofTemplate(
            templateId: "credential_default",
            proofType: .credential,
            titlePattern: "Credential Proof",
            bodyPattern: "This document proves that {recipient} holds the following credential, attested by {issuer}.",
            footerPattern: "Verify at: {verification_url}",
            includeQRCode: true,
            includeTimestamp: true
        )

        let ownershipTemplate = ProofTemplate(
            templateId: "ownership_default",
            proofType: .ownership,
            titlePattern: "Proof of Ownership",
            bodyPattern: "{recipient} is the verified owner of the described asset, as attested on-chain.",
            footerPattern: "Verify at: {verification_url}",
            includeQRCode: true,
            includeTimestamp: true
        )

        let agreementTemplate = ProofTemplate(
            templateId: "agreement_default",
            proofType: .agreement,
            titlePattern: "Agreement Proof",
            bodyPattern: "This document confirms that an agreement has been executed between the listed parties.",
            footerPattern: "Verify at: {verification_url}",
            includeQRCode: true,
            includeTimestamp: true
        )

        templates[.identity] = identityTemplate
        templates[.credential] = credentialTemplate
        templates[.ownership] = ownershipTemplate
        templates[.agreement] = agreementTemplate
    }

    private func buildProof(
        attestation: AttestationData,
        schema: EASSchema,
        proofType: ProofType,
        completion: @escaping (Result<VerifiableProof, ProofGenerationError>) -> Void
    ) {
        guard let template = templates[proofType] else {
            completion(.failure(.templateNotFound(proofType: proofType)))
            return
        }

        // Generate human-readable text
        let humanReadableText: String
        if let formatter = customFormatter {
            humanReadableText = formatter.format(attestation: attestation, schema: schema, template: template)
        } else {
            humanReadableText = formatProofDocument(
                attestation: attestation,
                schema: schema,
                template: template
            )
        }

        let proofId = UUID().uuidString
        let shortCode = generateShortCode(for: proofId)
        let verificationURL = verificationBaseURL.appendingPathComponent(shortCode)

        let qrCode = template.includeQRCode ? generateQRCode(for: verificationURL) : nil

        let proof = VerifiableProof(
            proofId: proofId,
            attestationUID: attestation.uid,
            humanReadableText: humanReadableText,
            verificationURL: verificationURL,
            qrCodeData: qrCode,
            generatedAt: Date(),
            expiresAt: attestation.expirationTime,
            issuer: attestation.attester,
            recipient: attestation.recipient,
            proofType: proofType,
            metadata: ProofMetadata(
                schemaName: schema.schema,
                chainId: BaseNetwork.chainId,
                blockNumber: 0,
                transactionHash: "",
                attestationTimestamp: attestation.time
            )
        )

        delegate?.proofGenerator(self, didGenerateProof: proof)
        completion(.success(proof))
    }

    private func formatProofDocument(attestation: AttestationData, schema: EASSchema, template: ProofTemplate) -> String {
        var document = ""
        document += "=== \(template.titlePattern) ===\n\n"

        let body = template.bodyPattern
            .replacingOccurrences(of: "{recipient}", with: formatAddress(attestation.recipient))
            .replacingOccurrences(of: "{issuer}", with: formatAddress(attestation.attester))
        document += body + "\n\n"

        document += convertToPlainLanguage(attestation: attestation, schema: schema)
        document += "\n\n"

        if template.includeTimestamp {
            document += "Generated: \(formatDate(Date()))\n"
        }

        let shortCode = generateShortCode(for: attestation.uid)
        let verifyURL = verificationBaseURL.appendingPathComponent(shortCode)
        let footer = template.footerPattern
            .replacingOccurrences(of: "{verification_url}", with: verifyURL.absoluteString)
        document += footer + "\n"

        return document
    }

    private func decodeAttestationData(_ data: Data, schema: EASSchema) -> [(String, String)] {
        // TODO: ABI-decode attestation data according to schema fields
        let fields = easManager.parseSchema(schema.schema)
        return fields.map { ($0.name, "<decoded_value>") }
    }

    private func fieldToPlainLanguage(fieldName: String, value: String) -> String {
        let readableName = fieldName
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        return "\(readableName): \(value)"
    }

    private func formatAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        let prefix = address.prefix(6)
        let suffix = address.suffix(4)
        return "\(prefix)...\(suffix)"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func generateShortCode(for identifier: String) -> String {
        // TODO: Generate URL-safe short code from identifier hash
        let hash = identifier.hashValue
        return String(format: "%08x", abs(hash))
    }
}
