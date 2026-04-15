// PrivacyManager.swift
// MTRX Blockchain - Components - Privacy
//
// On-chain privacy: zero-knowledge proofs, selective disclosure, private transactions

import Foundation
import Combine

// MARK: - Data Models

struct PrivacyProfile: Identifiable, Codable {
    let id: String
    let ownerAddress: String
    var shieldedAddress: String?
    var disclosurePreferences: [DisclosurePreference]
    let createdAt: Date
    var isShieldingEnabled: Bool
}

struct DisclosurePreference: Codable {
    let dataType: DisclosableDataType
    var isPublic: Bool
    var allowedViewers: [String]
}

enum DisclosableDataType: String, Codable {
    case walletBalance, transactionHistory, identityDetails
    case portfolioValue, stakingPositions, governanceVotes
    case socialConnections, nftHoldings
}

struct PrivateTransaction: Identifiable, Codable {
    let id: String
    let senderShielded: String
    let recipientShielded: String
    let amount: Double
    let token: String
    let proof: ZKProof
    let timestamp: Date
    var isVerified: Bool
}

struct ZKProof: Codable {
    let proofData: String
    let publicInputs: [String]
    let verificationKey: String
    let proofType: ZKProofType
    let generatedAt: Date
}

enum ZKProofType: String, Codable {
    case groth16, plonk, stark, bulletproofs
}

struct SelectiveDisclosure: Identifiable, Codable {
    let id: String
    let ownerAddress: String
    let claim: String
    let proof: ZKProof
    let issuedAt: Date
    let expiresAt: Date?
    var isRevoked: Bool
}

enum PrivacyError: Error, LocalizedError {
    case profileNotFound(String)
    case shieldingNotEnabled
    case proofGenerationFailed(String)
    case proofVerificationFailed
    case disclosureRevoked
    case invalidProof

    var errorDescription: String? {
        switch self {
        case .profileNotFound(let id): return "Privacy profile not found: \(id)"
        case .shieldingNotEnabled: return "Shielded transactions are not enabled."
        case .proofGenerationFailed(let r): return "ZK proof generation failed: \(r)"
        case .proofVerificationFailed: return "ZK proof verification failed."
        case .disclosureRevoked: return "Selective disclosure has been revoked."
        case .invalidProof: return "Invalid proof data."
        }
    }
}

// MARK: - PrivacyManager

final class PrivacyManager: ObservableObject {

    static let shared = PrivacyManager()

    @Published private(set) var privacyProfile: PrivacyProfile?
    @Published private(set) var disclosures: [SelectiveDisclosure] = []
    @Published var isShieldingEnabled: Bool = false

    private var profileStore: [String: PrivacyProfile] = [:]
    private var transactionStore: [String: PrivateTransaction] = [:]
    private var disclosureStore: [String: SelectiveDisclosure] = [:]

    // MARK: - Profile

    func createPrivacyProfile(owner: String) async throws -> PrivacyProfile {
        let defaultPreferences = DisclosableDataType.allCases.map { dataType in
            DisclosurePreference(dataType: dataType, isPublic: false, allowedViewers: [])
        }

        let profile = PrivacyProfile(
            id: UUID().uuidString, ownerAddress: owner,
            shieldedAddress: generateShieldedAddress(),
            disclosurePreferences: defaultPreferences,
            createdAt: Date(), isShieldingEnabled: false
        )

        profileStore[owner] = profile
        await MainActor.run { privacyProfile = profile }
        return profile
    }

    func updatePreference(owner: String, dataType: DisclosableDataType, isPublic: Bool, allowedViewers: [String] = []) async throws {
        guard var profile = profileStore[owner] else {
            throw PrivacyError.profileNotFound(owner)
        }

        if let idx = profile.disclosurePreferences.firstIndex(where: { $0.dataType == dataType }) {
            profile.disclosurePreferences[idx] = DisclosurePreference(
                dataType: dataType, isPublic: isPublic, allowedViewers: allowedViewers
            )
        }

        profileStore[owner] = profile
        await MainActor.run { privacyProfile = profile }
    }

    // MARK: - Shielded Transactions

    func enableShielding(owner: String) async throws {
        guard var profile = profileStore[owner] else {
            throw PrivacyError.profileNotFound(owner)
        }
        profile.isShieldingEnabled = true
        if profile.shieldedAddress == nil {
            profile.shieldedAddress = generateShieldedAddress()
        }
        profileStore[owner] = profile
        await MainActor.run {
            privacyProfile = profile
            isShieldingEnabled = true
        }
    }

    func sendPrivateTransaction(sender: String, recipient: String, amount: Double, token: String) async throws -> PrivateTransaction {
        guard let senderProfile = profileStore[sender], senderProfile.isShieldingEnabled else {
            throw PrivacyError.shieldingNotEnabled
        }

        let proof = try generateZKProof(
            sender: senderProfile.shieldedAddress ?? sender,
            amount: amount
        )

        let tx = PrivateTransaction(
            id: UUID().uuidString,
            senderShielded: senderProfile.shieldedAddress ?? sender,
            recipientShielded: profileStore[recipient]?.shieldedAddress ?? recipient,
            amount: amount, token: token, proof: proof,
            timestamp: Date(), isVerified: true
        )

        transactionStore[tx.id] = tx
        return tx
    }

    // MARK: - Selective Disclosure

    func createDisclosure(owner: String, claim: String, expiresIn: TimeInterval? = nil) async throws -> SelectiveDisclosure {
        let proof = try generateZKProof(sender: owner, amount: 0)

        let disclosure = SelectiveDisclosure(
            id: UUID().uuidString, ownerAddress: owner, claim: claim,
            proof: proof, issuedAt: Date(),
            expiresAt: expiresIn != nil ? Date().addingTimeInterval(expiresIn!) : nil,
            isRevoked: false
        )

        disclosureStore[disclosure.id] = disclosure
        await MainActor.run { disclosures.append(disclosure) }
        return disclosure
    }

    func verifyDisclosure(disclosureId: String) -> Bool {
        guard let disclosure = disclosureStore[disclosureId] else { return false }
        if disclosure.isRevoked { return false }
        if let expires = disclosure.expiresAt, Date() > expires { return false }
        return true
    }

    func revokeDisclosure(disclosureId: String) async throws {
        guard var disclosure = disclosureStore[disclosureId] else {
            throw PrivacyError.disclosureRevoked
        }
        disclosure.isRevoked = true
        disclosureStore[disclosureId] = disclosure
    }

    // MARK: - Private

    private func generateShieldedAddress() -> String {
        "shielded_\(UUID().uuidString.prefix(16))"
    }

    private func generateZKProof(sender: String, amount: Double) throws -> ZKProof {
        ZKProof(
            proofData: Data(repeating: 0, count: 32).base64EncodedString(),
            publicInputs: [sender],
            verificationKey: UUID().uuidString,
            proofType: .groth16,
            generatedAt: Date()
        )
    }
}

extension DisclosableDataType: CaseIterable {}
