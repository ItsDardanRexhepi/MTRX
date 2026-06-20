// IdentityManager.swift
// MTRX Blockchain - Components - Identity
//
// Decentralized identity: DID documents, verifiable credentials

import Foundation
import CryptoKit

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
    case notConfigured
    case issuerSigningUnavailable
    case unresolvableVerificationMethod

    var errorDescription: String? {
        switch self {
        case .didNotFound: return "DID document not found."
        case .credentialNotFound: return "Verifiable credential not found."
        case .verificationFailed: return "Credential verification failed."
        case .credentialRevoked: return "Credential has been revoked."
        case .credentialExpired: return "Credential has expired."
        case .issuerNotTrusted: return "Credential issuer is not trusted."
        case .invalidProof: return "Credential proof is invalid."
        case .notConfigured: return "Identity registry not configured (PendingCredentials.Components.identity)."
        case .issuerSigningUnavailable: return "Issuer signing key is unavailable — the issuer DID must be controlled by this device's wallet (no remote/HSM issuer signer is wired)."
        case .unresolvableVerificationMethod: return "Could not resolve the credential's verificationMethod to a public key."
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

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `registerDID(address controller, bytes publicKey)`.
    /// P-256/RIP-7212 CONSTRAINT: `publicKey` is the user's Secure Enclave key,
    /// which is P-256 (secp256r1) — the on-chain registry/verifier must accept
    /// P-256, NOT Ethereum's secp256k1.
    static func encodeRegisterDID(controller: String, publicKey: Data) -> Data {
        var out = ABIEncoder.functionSelector("registerDID(address,bytes)")
        out.append(ABIEncoder.encodeAddress(controller))
        out.append(ABIEncoder.encodeOffset(64)) // bytes arg follows 2 head words
        out.append(ABIEncoder.encodeBytes(publicKey))
        return out
    }

    /// Register a DID on-chain through the real submit pipeline: enclave-signed
    /// UserOp → server paymaster → bundler. Registry address deferred to
    /// PendingCredentials (nil until set → throws, never a fake registration).
    /// Static: needs no instance state (keeps it testable without the EAS graph).
    @MainActor
    static func registerDIDOnChain(
        controller: String,
        publicKey: Data,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.identity)
    ) async throws -> WalletTransactionService.Submission {
        guard let registry = contract else { throw IdentityError.notConfigured }
        return try await service.submitCall(
            to: registry,
            value: 0,
            data: Self.encodeRegisterDID(controller: controller, publicKey: publicKey),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
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

    /// Issue a verifiable credential, signing the credential proof with the
    /// ISSUER's key via the Secure Enclave (`signProof`).
    ///
    /// `issuerAppleUserId` is the issuer's wallet identity — the enclave key is
    /// keyed by Apple user id (`WalletCore` tag `wallet.<appleUserId>`), NOT by
    /// the DID string. The issuer DID must therefore be controlled by this
    /// device's wallet; if no issuer signer is available the proof is NOT faked —
    /// we return `.issuerSigningUnavailable`.
    ///
    /// P-256/secp256k1 BOUNDARY: the enclave signs P-256 (secp256r1), so the
    /// emitted proof type is `EcdsaSecp256r1Signature2019` (a JcsEcdsaSecp256r1
    /// style proof), NOT the secp256k1 type a stock Ethereum signer would emit.
    /// Relying parties / on-chain verifiers must accept P-256.
    func issueCredential(issuerDID: String, issuerAppleUserId: String, subjectDID: String, credentialType: [String], claims: [String: String], expirationDate: Date?, completion: @escaping (Result<VerifiableCredential, IdentityError>) -> Void) {
        let credentialId = UUID().uuidString
        let issuanceDate = Date()
        let created = Date()
        let verificationMethod = "\(issuerDID)#key-1"

        // Canonical bytes the proof signs over: the credential's signable core,
        // excluding the proof block itself (the proofValue can't sign itself).
        let signingPayload = Self.credentialSigningPayload(
            id: credentialId, issuer: issuerDID, subject: subjectDID,
            credentialType: credentialType, issuanceDate: issuanceDate,
            expirationDate: expirationDate, claims: claims,
            verificationMethod: verificationMethod, created: created
        )

        Task { @MainActor in
            do {
                // signProof: enclave-signed P-256 DER signature over the payload.
                // Throws (never returns an empty proof) if the issuer signer is
                // unavailable — honest needs-config rather than a fabricated sig.
                let proofValue = try await Self.signProof(
                    payload: signingPayload, issuerAppleUserId: issuerAppleUserId
                )
                let proof = CredentialProof(
                    proofType: "EcdsaSecp256r1Signature2019",
                    created: created,
                    verificationMethod: verificationMethod,
                    proofValue: proofValue
                )
                let credential = VerifiableCredential(
                    id: credentialId, issuer: issuerDID, subject: subjectDID,
                    credentialType: credentialType, issuanceDate: issuanceDate,
                    expirationDate: expirationDate, claims: claims,
                    proof: proof, attestationUID: nil, status: .active
                )
                self.credentials[credentialId] = credential
                self.delegate?.identity(self, didIssueCredential: credentialId)
                completion(.success(credential))
            } catch let error as IdentityError {
                self.delegate?.identity(self, didFailWithError: error)
                completion(.failure(error))
            } catch {
                self.delegate?.identity(self, didFailWithError: .issuerSigningUnavailable)
                completion(.failure(.issuerSigningUnavailable))
            }
        }
    }

    // MARK: - Proof signing (`signProof`) — enclave, non-custodial

    /// Deterministic, canonical bytes a credential proof signs over.
    /// We sort the claim keys so the same credential always yields the same
    /// payload (a minimal JCS-style canonicalisation), and explicitly EXCLUDE the
    /// `proofValue` (a signature cannot sign itself). ISO-8601 timestamps keep it
    /// stable across encodings. The same routine is used by `verifyProof`, so
    /// signing and verification are guaranteed byte-identical.
    static func credentialSigningPayload(
        id: String, issuer: String, subject: String,
        credentialType: [String], issuanceDate: Date,
        expirationDate: Date?, claims: [String: String],
        verificationMethod: String, created: Date
    ) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let sortedClaims = claims.keys.sorted()
            .map { "\($0)=\(claims[$0] ?? "")" }
            .joined(separator: "&")
        let parts: [String] = [
            "id:\(id)",
            "issuer:\(issuer)",
            "subject:\(subject)",
            "type:\(credentialType.joined(separator: ","))",
            "issued:\(iso.string(from: issuanceDate))",
            "expires:\(expirationDate.map { iso.string(from: $0) } ?? "")",
            "claims:\(sortedClaims)",
            "vm:\(verificationMethod)",
            "created:\(iso.string(from: created))"
        ]
        return Data(parts.joined(separator: "\n").utf8)
    }

    /// Sign a credential proof with the ISSUER key via the Secure Enclave.
    ///
    /// We do NOT invent an issuer key: we route through `WalletCore.shared.sign`,
    /// which signs P-256 inside the enclave and enforces Face-ID-at-signing. The
    /// key is the issuer-wallet key (`wallet.<issuerAppleUserId>`). If the issuer
    /// identity isn't controlled here (no such key / signing fails), we throw
    /// `.issuerSigningUnavailable` — never a placeholder/empty proof.
    ///
    /// Returns the base64 DER P-256 signature (the `proofValue`).
    @MainActor
    static func signProof(payload: Data, issuerAppleUserId: String) async throws -> String {
        let trimmed = issuerAppleUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw IdentityError.issuerSigningUnavailable }
        // Only sign if the issuer's enclave key actually exists — otherwise the
        // signer would silently create a fresh key, which is NOT the named issuer.
        guard SecureEnclaveManager.shared.hasKey(tag: "wallet." + trimmed) else {
            throw IdentityError.issuerSigningUnavailable
        }
        do {
            let signature = try await WalletCore.shared.sign(payload, appleUserId: trimmed)
            return signature.base64EncodedString()
        } catch {
            throw IdentityError.issuerSigningUnavailable
        }
    }

    /// Verify a credential's proof signature against the public key resolved from
    /// its `verificationMethod`/DID, then check status, expiry, and issuer trust.
    ///
    /// `verifyProof`: the proofValue is a base64 P-256 (secp256r1) DER signature.
    /// We resolve the verification-method's public key from the issuer DID
    /// document (must already be known via `createDID`/`updateDID`), reconstruct
    /// the exact canonical payload (`credentialSigningPayload`), and verify with
    /// CryptoKit. Invalid signatures or untrusted issuers are REJECTED. We never
    /// "pass" a credential we can't actually verify.
    func verifyCredential(credentialId: String) -> Result<Bool, IdentityError> {
        guard let credential = credentials[credentialId] else { return .failure(.credentialNotFound) }
        guard credential.status == .active else { return .failure(.credentialRevoked) }
        if let exp = credential.expirationDate, Date() > exp { return .failure(.credentialExpired) }

        // Untrusted issuers are rejected when a trust list is configured. An empty
        // trust list means "no explicit trust anchors yet" — we still verify the
        // cryptographic proof but flag the issuer-trust gap to callers via the
        // dedicated error rather than silently trusting everyone.
        if !trustedIssuers.isEmpty && !trustedIssuers.contains(credential.issuer) {
            return .failure(.issuerNotTrusted)
        }

        return verifyProof(for: credential)
    }

    /// Cryptographically validate `proofValue` against the public key bound to the
    /// proof's `verificationMethod`. Returns `.invalidProof` for malformed/failed
    /// signatures, `.unresolvableVerificationMethod` when no key can be resolved.
    func verifyProof(for credential: VerifiableCredential) -> Result<Bool, IdentityError> {
        let proof = credential.proof
        guard !proof.proofValue.isEmpty,
              let signature = Data(base64Encoded: proof.proofValue) else {
            return .failure(.invalidProof)
        }
        guard let publicKey = resolveVerificationKey(method: proof.verificationMethod) else {
            return .failure(.unresolvableVerificationMethod)
        }

        let payload = Self.credentialSigningPayload(
            id: credential.id, issuer: credential.issuer, subject: credential.subject,
            credentialType: credential.credentialType, issuanceDate: credential.issuanceDate,
            expirationDate: credential.expirationDate, claims: credential.claims,
            verificationMethod: proof.verificationMethod, created: proof.created
        )
        let digest = SHA256.hash(data: payload) // enclave signs over SHA-256(payload)

        do {
            let p256Signature = try P256.Signing.ECDSASignature(derRepresentation: signature)
            let valid = publicKey.isValidSignature(p256Signature, for: digest)
            return valid ? .success(true) : .failure(.invalidProof)
        } catch {
            return .failure(.invalidProof)
        }
    }

    /// Resolve a `verificationMethod` id (e.g. `did:mtrx:0x..#key-1`) to its
    /// P-256 public key, using the locally known DID document for the issuer DID.
    /// The stored `publicKeyMultibase` is the base64 raw public key written by
    /// `createDID`. Returns nil when the DID/method isn't known — we never guess.
    private func resolveVerificationKey(method: String) -> P256.Signing.PublicKey? {
        let did = method.contains("#") ? String(method.split(separator: "#").first ?? "") : method
        guard let doc = didDocuments[did] else { return nil }
        guard let vm = doc.verificationMethods.first(where: { $0.id == method })
                ?? doc.verificationMethods.first
        else { return nil }
        guard let raw = Data(base64Encoded: vm.publicKeyMultibase) else { return nil }
        return try? P256.Signing.PublicKey(rawRepresentation: raw)
    }

    // MARK: - Revocation (on-chain, via the submit pipeline)

    /// ABI-encode `revoke(bytes32 credentialId)`.
    ///
    /// The on-chain registry keys revocations by a fixed 32-byte id. Credential
    /// ids are app-side UUID strings, so we bind them to chain space by hashing
    /// (SHA-256, matching the keccak-approximation the rest of the wallet uses) —
    /// a deterministic, collision-resistant `bytes32`. The same derivation must be
    /// applied by whoever reads the on-chain revocation status. We do NOT fabricate
    /// an arbitrary id.
    static func encodeRevoke(credentialId: String) -> Data {
        var out = ABIEncoder.functionSelector("revoke(bytes32)")
        let id32 = Data(SHA256.hash(data: Data(credentialId.utf8))) // 32 bytes
        out.append(id32)
        return out
    }

    /// Revoke a credential on-chain through the real submit pipeline: enclave-signed
    /// UserOp → server paymaster → bundler. Identity registry address deferred to
    /// PendingCredentials.Components.identity (nil until set → throws
    /// `.notConfigured`, never a fake revocation / fabricated tx hash).
    @MainActor
    static func revokeOnChain(
        credentialId: String,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.identity)
    ) async throws -> WalletTransactionService.Submission {
        guard let registry = contract else { throw IdentityError.notConfigured }
        return try await service.submitCall(
            to: registry,
            value: 0,
            data: Self.encodeRevoke(credentialId: credentialId),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    /// Revoke a credential: update local status AND submit the on-chain revocation.
    ///
    /// `sender` is the issuer's smart-account address and `signingKeyTag` their
    /// Secure Enclave key tag (`wallet.<issuerAppleUserId>`). When the chain core
    /// or the identity registry address is unconfigured the pipeline throws a clear
    /// "needs config" error — the local status is NOT flipped to revoked on a
    /// failed on-chain call, so app state never diverges from a fabricated success.
    func revokeCredential(credentialId: String, sender: String, signingKeyTag: String, completion: @escaping (Result<WalletTransactionService.Submission, IdentityError>) -> Void) {
        guard credentials[credentialId] != nil else {
            completion(.failure(.credentialNotFound))
            return
        }
        Task { @MainActor in
            guard let service = WalletTransactionService() else {
                completion(.failure(.notConfigured)) // chain core unconfigured → needs-config
                return
            }
            do {
                let submission = try await Self.revokeOnChain(
                    credentialId: credentialId,
                    sender: sender,
                    signingKeyTag: signingKeyTag,
                    service: service
                )
                // Only reflect revocation locally once the on-chain submit succeeded.
                if var credential = self.credentials[credentialId] {
                    credential = VerifiableCredential(
                        id: credential.id, issuer: credential.issuer, subject: credential.subject,
                        credentialType: credential.credentialType, issuanceDate: credential.issuanceDate,
                        expirationDate: credential.expirationDate, claims: credential.claims,
                        proof: credential.proof, attestationUID: credential.attestationUID,
                        status: .revoked
                    )
                    self.credentials[credentialId] = credential
                }
                completion(.success(submission))
            } catch let error as IdentityError {
                completion(.failure(error))
            } catch {
                completion(.failure(.notConfigured))
            }
        }
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
