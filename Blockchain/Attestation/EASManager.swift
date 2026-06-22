// EASManager.swift
// MTRX Blockchain - Attestation
//
// Ethereum Attestation Service (EAS) Schema 348 management

import Foundation

// MARK: - Protocols

protocol EASManagerDelegate: AnyObject {
    func easManager(_ manager: EASManager, didCreateAttestation uid: String)
    func easManager(_ manager: EASManager, didRevokeAttestation uid: String)
    func easManager(_ manager: EASManager, didFailWithError error: EASError)
}

protocol EASResolverContract {
    func attest(attestation: AttestationData) async throws -> Bool
    func revoke(uid: String) async throws -> Bool
    func isPayable() -> Bool
}

// MARK: - Data Models

struct EASSchema: Codable {
    let uid: String
    let schema: String
    let resolverAddress: String
    let revocable: Bool
    let registeredAt: Date

    static let mtrxSchemaId: UInt64 = 348
}

struct AttestationData: Codable {
    let uid: String
    let schemaUID: String
    let recipient: String
    let attester: String
    let time: Date
    let expirationTime: Date?
    let revocationTime: Date?
    let data: Data
    let isRevoked: Bool

    var isExpired: Bool {
        guard let expiration = expirationTime else { return false }
        return Date() > expiration
    }

    var isValid: Bool {
        return !isRevoked && !isExpired
    }
}

struct AttestationRequest {
    let schemaUID: String
    let recipient: String
    let expirationTime: Date?
    let revocable: Bool
    let data: Data
    let value: UInt64
}

struct SchemaField {
    let name: String
    let fieldType: SchemaFieldType
    let isRequired: Bool
}

enum SchemaFieldType: String {
    case address
    case string
    case uint256
    case bytes32
    case bool
    case bytes
    case uint8
}

enum EASError: Error, LocalizedError {
    case schemaNotFound
    case attestationNotFound(uid: String)
    case invalidSchema
    case attestationRevoked
    case attestationExpired
    case resolverRejected
    case encodingFailed
    case verificationFailed(reason: String)
    case networkError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .schemaNotFound: return "EAS schema not found."
        case .attestationNotFound(let uid): return "Attestation not found: \(uid)"
        case .invalidSchema: return "Invalid schema definition."
        case .attestationRevoked: return "Attestation has been revoked."
        case .attestationExpired: return "Attestation has expired."
        case .resolverRejected: return "Resolver contract rejected the attestation."
        case .encodingFailed: return "Failed to encode attestation data."
        case .verificationFailed(let reason): return "Verification failed: \(reason)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

// MARK: - EASManager

final class EASManager {

    // MARK: - Constants

    /// EAS contract address on Base
    static let easContractAddress = "0x4200000000000000000000000000000000000021"

    /// Schema Registry contract address on Base
    static let schemaRegistryAddress = "0x4200000000000000000000000000000000000020"

    // MARK: - Properties

    weak var delegate: EASManagerDelegate?

    /// Cached schemas
    private var schemaCache: [String: EASSchema] = [:]

    /// Cached attestations
    private var attestationCache: [String: AttestationData] = [:]

    /// Resolver contracts mapped by address
    private var resolvers: [String: EASResolverContract] = [:]

    /// Network provider for on-chain calls
    private let network: BaseNetwork

    /// ERC-4337 manager for transaction submission
    private let accountManager: ERC4337Manager

    private let processingQueue = DispatchQueue(label: "com.mtrx.eas.processing", qos: .userInitiated)

    // MARK: - Initialization

    init(network: BaseNetwork, accountManager: ERC4337Manager) {
        self.network = network
        self.accountManager = accountManager
    }

    // MARK: - Schema Management

    /// Register a new schema on EAS
    func registerSchema(
        schema: String,
        resolverAddress: String,
        revocable: Bool,
        completion: @escaping (Result<String, EASError>) -> Void
    ) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // TODO: ABI-encode register(string schema, address resolver, bool revocable)
            // Submit via ERC-4337 UserOperation to Schema Registry
            let schemaUID = self.computeSchemaUID(schema: schema, resolver: resolverAddress, revocable: revocable)

            let easSchema = EASSchema(
                uid: schemaUID,
                schema: schema,
                resolverAddress: resolverAddress,
                revocable: revocable,
                registeredAt: Date()
            )
            self.schemaCache[schemaUID] = easSchema
            completion(.success(schemaUID))
        }
    }

    /// Get a schema by its UID
    func getSchema(uid: String, completion: @escaping (Result<EASSchema, EASError>) -> Void) {
        if let cached = schemaCache[uid] {
            completion(.success(cached))
            return
        }

        // TODO: Call getSchema(bytes32) on Schema Registry contract
        completion(.failure(.schemaNotFound))
    }

    /// Build the MTRX platform schema (Schema 348)
    func getMTRXSchema() -> String {
        return "address subject, string category, string claim, bytes32 evidenceHash, uint64 timestamp, bool verified"
    }

    /// Parse schema string into typed fields
    func parseSchema(_ schema: String) -> [SchemaField] {
        let components = schema.components(separatedBy: ", ")
        return components.compactMap { component in
            let parts = component.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
            guard parts.count >= 2,
                  let fieldType = SchemaFieldType(rawValue: parts[0]) else { return nil }
            return SchemaField(name: parts[1], fieldType: fieldType, isRequired: true)
        }
    }

    // MARK: - Attestation Creation

    /// Create a new on-chain attestation
    func createAttestation(
        request: AttestationRequest,
        completion: @escaping (Result<AttestationData, EASError>) -> Void
    ) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            // Validate schema exists
            self.getSchema(uid: request.schemaUID) { schemaResult in
                switch schemaResult {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let schema):
                    // Encode attestation request
                    guard let calldata = self.encodeAttestRequest(request, schema: schema) else {
                        completion(.failure(.encodingFailed))
                        return
                    }

                    // Submit via ERC-4337
                    let opResult = self.accountManager.buildUserOperation(
                        to: EASManager.easContractAddress,
                        value: request.value,
                        data: calldata,
                        sponsorGas: true
                    )

                    switch opResult {
                    case .failure:
                        completion(.failure(.networkError(underlying: NSError(domain: "EAS", code: -1))))
                    case .success(let operation):
                        self.accountManager.submitOperation(operation) { submitResult in
                            switch submitResult {
                            case .failure:
                                completion(.failure(.networkError(underlying: NSError(domain: "EAS", code: -2))))
                            case .success(let opHash):
                                let attestation = AttestationData(
                                    uid: opHash,
                                    schemaUID: request.schemaUID,
                                    recipient: request.recipient,
                                    attester: self.accountManager.accountAddress ?? "",
                                    time: Date(),
                                    expirationTime: request.expirationTime,
                                    revocationTime: nil,
                                    data: request.data,
                                    isRevoked: false
                                )
                                self.attestationCache[opHash] = attestation
                                self.delegate?.easManager(self, didCreateAttestation: opHash)
                                completion(.success(attestation))
                            }
                        }
                    }
                }
            }
        }
    }

    /// Create multiple attestations in a batch
    func createBatchAttestations(
        requests: [AttestationRequest],
        completion: @escaping (Result<[String], EASError>) -> Void
    ) {
        // Honest failure: multiAttest ABI-encoding + submission is not implemented, so
        // no attestations are created. Return failure rather than success([]), which
        // would imply the batch was written on-chain when nothing was.
        completion(.failure(.verificationFailed(reason: "Batch attestation is not available yet.")))
    }

    // MARK: - Attestation Verification

    /// Verify an attestation by its UID
    func verifyAttestation(uid: String, completion: @escaping (Result<AttestationData, EASError>) -> Void) {
        // Check cache first
        if let cached = attestationCache[uid] {
            if cached.isRevoked {
                completion(.failure(.attestationRevoked))
            } else if cached.isExpired {
                completion(.failure(.attestationExpired))
            } else {
                completion(.success(cached))
            }
            return
        }

        // TODO: Call getAttestation(bytes32) on EAS contract
        completion(.failure(.attestationNotFound(uid: uid)))
    }

    /// Verify attestation and check resolver conditions
    func verifyWithResolver(uid: String, completion: @escaping (Result<Bool, EASError>) -> Void) {
        verifyAttestation(uid: uid) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let attestation):
                self?.getSchema(uid: attestation.schemaUID) { schemaResult in
                    switch schemaResult {
                    case .failure(let error):
                        completion(.failure(error))
                    case .success(let schema):
                        guard !schema.resolverAddress.isEmpty,
                              schema.resolverAddress != "0x0000000000000000000000000000000000000000" else {
                            completion(.success(true))
                            return
                        }
                        // Honest failure: the resolver-contract check is not implemented,
                        // so we cannot assert this attestation satisfies its resolver
                        // conditions. Return failure rather than a fake success(true).
                        // (The no-resolver branch above legitimately succeeds — there is
                        // nothing to check there.)
                        completion(.failure(.verificationFailed(reason: "Resolver verification is not available yet.")))
                    }
                }
            }
        }
    }

    // MARK: - Attestation Revocation

    /// Revoke an attestation
    func revokeAttestation(uid: String, completion: @escaping (Result<Void, EASError>) -> Void) {
        guard var attestation = attestationCache[uid] else {
            completion(.failure(.attestationNotFound(uid: uid)))
            return
        }

        // TODO: ABI-encode revoke(bytes32) and submit via ERC-4337
        attestation = AttestationData(
            uid: attestation.uid,
            schemaUID: attestation.schemaUID,
            recipient: attestation.recipient,
            attester: attestation.attester,
            time: attestation.time,
            expirationTime: attestation.expirationTime,
            revocationTime: Date(),
            data: attestation.data,
            isRevoked: true
        )
        attestationCache[uid] = attestation
        delegate?.easManager(self, didRevokeAttestation: uid)
        completion(.success(()))
    }

    // MARK: - Query

    /// Get all attestations for a recipient
    func getAttestations(forRecipient address: String) -> [AttestationData] {
        return attestationCache.values.filter { $0.recipient == address && $0.isValid }
    }

    /// Get all attestations by an attester
    func getAttestations(byAttester address: String) -> [AttestationData] {
        return attestationCache.values.filter { $0.attester == address }
    }

    /// Get attestations for a specific schema
    func getAttestations(forSchema schemaUID: String) -> [AttestationData] {
        return attestationCache.values.filter { $0.schemaUID == schemaUID && $0.isValid }
    }

    // MARK: - Private Helpers

    /// EAS schema UID = keccak256(abi.encodePacked(schema, resolver, revocable)).
    /// Real keccak over the packed encoding — not a random id.
    private func computeSchemaUID(schema: String, resolver: String, revocable: Bool) -> String {
        var packed = Data()
        packed.append(Data(schema.utf8))           // string → raw UTF-8 bytes (packed)
        packed.append(Self.addressBytes(resolver)) // address → 20 bytes
        packed.append(revocable ? 0x01 : 0x00)      // bool → 1 byte
        let hash = Keccak256.hash(data: packed)
        return "0x" + hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Parse a hex address into exactly 20 bytes (left-padded / truncated).
    private static func addressBytes(_ hex: String) -> Data {
        let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        var bytes = Data()
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            if let byte = UInt8(cleaned[index..<next], radix: 16) { bytes.append(byte) }
            index = next
        }
        if bytes.count < 20 { return Data(repeating: 0, count: 20 - bytes.count) + bytes }
        if bytes.count > 20 { return bytes.suffix(20) }
        return bytes
    }

    /// EAS attest() calldata encoder. Intentionally returns nil until the full
    /// nested-tuple ABI encoder is wired — callers treat nil as "not available"
    /// and must not submit. (Returns nil, never fabricated/empty calldata.)
    private func encodeAttestRequest(_ request: AttestationRequest, schema: EASSchema) -> Data? {
        return nil
    }
}
