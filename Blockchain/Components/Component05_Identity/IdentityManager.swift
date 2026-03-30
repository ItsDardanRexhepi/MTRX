// IdentityManager.swift
// MTRX Blockchain - Components - Identity
//
// Decentralized identity: DID documents, verifiable credentials

import Foundation

// MARK: - Protocols

protocol IdentityManagerDelegate: AnyObject {
    func identity(_ manager: IdentityManager, didCreateDID did: String)
    func identity(_ manager: IdentityManager, didIssueCredential credentialId: String)
    func identity(_ manager: IdentityManager, didFailWithError error: IdentityError)
}

// MARK: - Data Models

struct DIDDocument: Codable {
    let id: String // did:mtrx:<address>
    let controller: String
    let verificationMethods: [VerificationMethod]
    let authenticationMethods: [String]
    let serviceEndpoints: [ServiceEndpoint]
    let created: Date
    let updated: Date
}

struct VerificationMethod: Codable {
    let id: String
    let methodType: String
    let controller: String
    let publicKeyMultibase: String
}

struct ServiceEndpoint: Codable {
    let id: String
    let serviceType: String
    let serviceEndpoint: String
}

struct VerifiableCredential: Codable {
    let id: String
    let issuer: String
    let subject: String
    let credentialType: [String]
    let issuanceDate: Date
    let expirationDate: Date?
    let claims: [String: String]
    let proof: CredentialProof
    let attestationUID: String?
    let status: CredentialStatus
}

struct CredentialProof: Codable {
    let proofType: String
    let created: Date
    let verificationMethod: String
    let proofValue: String
}

enum CredentialStatus: String, Codable {
    case active, revoked, expired, suspended
}

enum IdentityError: Error, LocalizedError {
    case didNotFound
    case credentialNotFound
    case verificationFailed
    case credentialRevoked
    case credentialExpired
    case issuerNotTrusted
    case invalidProof

    var errorDescription: String? {
        switch self {
        case .didNotFound: return "DID document not found."
        case .credentialNotFound: return "Verifiable credential not found."
        case .verificationFailed: return "Credential verification failed."
        case .credentialRevoked: return "Credential has been revoked."
        case .credentialExpired: return "Credential has expired."
        case .issuerNotTrusted: return "Credential issuer is not trusted."
        case .invalidProof: return "Credential proof is invalid."
        }
    }
}

// MARK: - IdentityManager

final class IdentityManager {

    // MARK: - Properties

    weak var delegate: IdentityManagerDelegate?

    private let erc4337Manager: ERC4337Manager
    private let easManager: EASManager
    private var didDocuments: [String: DIDDocument] = [:]
    private var credentials: [String: VerifiableCredential] = [:]
    private var trustedIssuers: Set<String> = []
    private let processingQueue = DispatchQueue(label: "com.mtrx.identity", qos: .userInitiated)

    // MARK: - Initialization

    init(erc4337Manager: ERC4337Manager, easManager: EASManager) {
        self.erc4337Manager = erc4337Manager
        self.easManager = easManager
    }

    // MARK: - DID Management

    /// Create a new DID document
    func createDID(controller: String, publicKey: Data, completion: @escaping (Result<DIDDocument, IdentityError>) -> Void) {
        let did = "did:mtrx:\(controller)"
        let verificationMethod = VerificationMethod(
            id: "\(did)#key-1",
            methodType: "EcdsaSecp256k1VerificationKey2019",
            controller: did,
            publicKeyMultibase: publicKey.base64EncodedString()
        )
        let doc = DIDDocument(
            id: did, controller: controller,
            verificationMethods: [verificationMethod],
            authenticationMethods: ["\(did)#key-1"],
            serviceEndpoints: [],
            created: Date(), updated: Date()
        )
        didDocuments[did] = doc
        delegate?.identity(self, didCreateDID: did)
        completion(.success(doc))
    }

    /// Resolve a DID to its document
    func resolveDID(_ did: String) -> Result<DIDDocument, IdentityError> {
        guard let doc = didDocuments[did] else { return .failure(.didNotFound) }
        return .success(doc)
    }

    /// Update a DID document
    func updateDID(_ did: String, serviceEndpoints: [ServiceEndpoint]?, completion: @escaping (Result<DIDDocument, IdentityError>) -> Void) {
        guard var doc = didDocuments[did] else {
            completion(.failure(.didNotFound))
            return
        }
        doc = DIDDocument(
            id: doc.id, controller: doc.controller,
            verificationMethods: doc.verificationMethods,
            authenticationMethods: doc.authenticationMethods,
            serviceEndpoints: serviceEndpoints ?? doc.serviceEndpoints,
            created: doc.created, updated: Date()
        )
        didDocuments[did] = doc
        completion(.success(doc))
    }

    // MARK: - Verifiable Credentials

    /// Issue a verifiable credential
    func issueCredential(issuerDID: String, subjectDID: String, credentialType: [String], claims: [String: String], expirationDate: Date?, completion: @escaping (Result<VerifiableCredential, IdentityError>) -> Void) {
        let credentialId = UUID().uuidString
        let proof = CredentialProof(
            proofType: "EcdsaSecp256k1Signature2019",
            created: Date(),
            verificationMethod: "\(issuerDID)#key-1",
            proofValue: "" // TODO: Sign with issuer key
        )
        let credential = VerifiableCredential(
            id: credentialId, issuer: issuerDID, subject: subjectDID,
            credentialType: credentialType, issuanceDate: Date(),
            expirationDate: expirationDate, claims: claims,
            proof: proof, attestationUID: nil, status: .active
        )
        credentials[credentialId] = credential
        delegate?.identity(self, didIssueCredential: credentialId)
        completion(.success(credential))
    }

    /// Verify a credential
    func verifyCredential(credentialId: String) -> Result<Bool, IdentityError> {
        guard let credential = credentials[credentialId] else { return .failure(.credentialNotFound) }
        guard credential.status == .active else { return .failure(.credentialRevoked) }
        if let exp = credential.expirationDate, Date() > exp { return .failure(.credentialExpired) }
        // TODO: Verify proof signature
        return .success(true)
    }

    /// Revoke a credential
    func revokeCredential(credentialId: String, completion: @escaping (Result<Void, IdentityError>) -> Void) {
        guard credentials[credentialId] != nil else {
            completion(.failure(.credentialNotFound))
            return
        }
        // TODO: Update on-chain revocation status
        completion(.success(()))
    }

    // MARK: - Trust Management

    func addTrustedIssuer(_ did: String) { trustedIssuers.insert(did) }
    func removeTrustedIssuer(_ did: String) { trustedIssuers.remove(did) }
    func isIssuerTrusted(_ did: String) -> Bool { return trustedIssuers.contains(did) }

    // MARK: - Query

    func getCredentials(for subjectDID: String) -> [VerifiableCredential] {
        return credentials.values.filter { $0.subject == subjectDID && $0.status == .active }
    }
}
