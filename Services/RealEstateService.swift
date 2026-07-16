// RealEstateService.swift
// MTRX — typed client for the Real-Estate Escrow Engine (/api/v1/realestate/*).
//
// Every model mirrors a documented backend response (0pnMatrx/REAL_ESTATE.md);
// the wire is snake_case (auto-converted) and timestamps are epoch seconds
// (Double), NOT ISO strings — the backend returns time.time() floats.
//
// Honest states are first-class, never invented:
//   • feature disabled server-side  -> every route HTTP 403 -> surfaced as
//     MTRXAPIError.securityBlocked (isSecurityBlock); the UI shows "coming soon".
//   • contracts not deployed         -> a 200 whose data.status == "not_deployed".
//   • not transaction-ready          -> data.status == "not_ready" + named blockers.
// Nothing here fabricates a property, a readiness, or a purchase result.

import Foundation

// MARK: - Models

struct REAddress: Codable, Hashable {
    let line1: String?
    let city: String?
    let state: String?
    let zip: String?

    /// Human one-liner from whatever fields the record carries.
    var display: String {
        [line1, [city, state].compactMap { $0 }.joined(separator: ", "), zip]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
    var shortCity: String { [city, state].compactMap { $0 }.joined(separator: ", ") }
}

struct REProperty: Codable, Identifiable, Hashable {
    let id: String
    let address: REAddress
    let priceWei: String
    let sellerWallet: String
    let status: String              // draft | listed | under_escrow | sold | delisted
    let deedTokenId: String?
    let createdAt: Double?
    let updatedAt: Double?

    var isListed: Bool { status == "listed" }
    var hasDeed: Bool { !(deedTokenId ?? "").isEmpty }
}

struct RETimestampedDoc: Codable, Identifiable, Hashable {
    let id: String
    let propertyId: String?
    let docType: String
    let contentHash: String?
    let storageRef: String?
    let storageStatus: String?      // stored | not_stored | hash_only
    let attestationRef: String?
    let attestationStatus: String?  // attested | queued | skipped | unattested
    let uploadedAt: Double?
    let expiresAt: Double?
    let supersededBy: String?

    var isVerified: Bool { attestationStatus == "attested" }
}

struct REDocumentsResponse: Codable {
    let current: [String: RETimestampedDoc]
    let history: [RETimestampedDoc]?
}

struct REBlocker: Codable, Identifiable, Hashable {
    var id: String { "\(item)-\(reason)" }
    let item: String                // e.g. title_report, proof_of_funds
    let reason: String              // missing | stale | unverified | insufficient
    let daysStale: Int?
    let detail: String?
}

struct REReadiness: Codable, Hashable {
    let ready: Bool
    let blockers: [REBlocker]
    let checkedAt: Double?
}

struct REStateHop: Codable, Hashable {
    let state: String
    let at: Double?
}

struct REEscrow: Codable, Identifiable, Hashable {
    let id: String
    let propertyId: String
    let buyerWallet: String
    let amountWei: String
    let state: String               // initiated | funds_locked | settled | offchain_recording_pending | complete | refunded
    let readinessSnapshot: REReadiness?
    let attestationRefs: [String: String]?
    let txHashes: [String: String]?
    let history: [REStateHop]?
    let createdAt: Double?
    let updatedAt: Double?
}

struct RESettlement: Codable {
    let to: String
    let valueWei: String
    let data: String
    let description: String?
    let gasSponsorship: String?
}

/// The one-tap purchase response — a status-bearing union (prepared / not_ready /
/// not_deployed). Optional fields are populated per status; nothing is faked.
struct REPurchaseResponse: Codable {
    let status: String              // prepared | not_ready | not_deployed
    let escrow: REEscrow?
    let settlement: RESettlement?
    let readiness: REReadiness?
    let missing: [String]?
    let message: String?
    let next: String?
}

struct REConfirmResponse: Codable {
    let status: String              // settled | pending | failed | not_settlement | not_deployed
    let escrow: REEscrow?
    let honestNote: String?
    let message: String?
}

/// Buyer proof-of-funds verification — also a status-bearing union
/// (verified / insufficient_funds / none / not_deployed).
struct REVerification: Codable {
    let id: String?
    let buyerWallet: String?
    let method: String?
    let status: String?             // verified | insufficient_funds | none | not_deployed
    let thresholdWei: String?
    let details: [String: String]?
    let attestationStatus: String?
    let verifiedAt: Double?
    let expiresAt: Double?
    let missing: [String]?
    let message: String?

    var isVerified: Bool { status == "verified" }
    var provenBalanceWei: String? { details?["balance_wei"] }
}

// MARK: - Service

@MainActor
final class RealEstateService {

    static let shared = RealEstateService()
    private let api = MTRXAPIClient.shared
    private let base = "/api/v1/realestate"

    private init() {}

    // ── Reads ────────────────────────────────────────────────────────
    func listProperties(status: String? = nil) async throws -> [REProperty] {
        let q = status.map { [URLQueryItem(name: "status", value: $0)] }
        return try await api.getEnveloped(path: "\(base)/properties", queryItems: q)
    }

    func getProperty(id: String) async throws -> REProperty {
        try await api.getEnveloped(path: "\(base)/properties/\(id)")
    }

    func getDocuments(propertyId: String, includeHistory: Bool = false) async throws -> REDocumentsResponse {
        let q = includeHistory ? [URLQueryItem(name: "history", value: "1")] : nil
        return try await api.getEnveloped(path: "\(base)/properties/\(propertyId)/documents", queryItems: q)
    }

    func getReadiness(propertyId: String, buyer: String) async throws -> REReadiness {
        let q = buyer.isEmpty ? nil : [URLQueryItem(name: "buyer", value: buyer)]
        return try await api.getEnveloped(path: "\(base)/properties/\(propertyId)/readiness", queryItems: q)
    }

    func documentsExpiring(days: Int = 14) async throws -> [RETimestampedDoc] {
        try await api.getEnveloped(path: "\(base)/documents/expiring",
                                   queryItems: [URLQueryItem(name: "days", value: String(days))])
    }

    func getBuyerVerification(wallet: String) async throws -> REVerification {
        try await api.getEnveloped(path: "\(base)/buyers/\(wallet)/verification")
    }

    func getEscrow(id: String) async throws -> REEscrow {
        try await api.getEnveloped(path: "\(base)/escrow/\(id)")
    }

    // ── Writes ───────────────────────────────────────────────────────
    func verifyBuyer(buyer: String, method: String = "wallet_balance",
                     thresholdWei: String) async throws -> REVerification {
        struct Body: Encodable { let buyer: String; let method: String; let thresholdWei: String }
        return try await api.postEnveloped(
            path: "\(base)/buyers/verify",
            body: Body(buyer: buyer, method: method, thresholdWei: thresholdWei))
    }

    func executePurchase(buyer: String, propertyId: String) async throws -> REPurchaseResponse {
        struct Body: Encodable { let buyer: String; let propertyId: String }
        return try await api.postEnveloped(
            path: "\(base)/purchase", body: Body(buyer: buyer, propertyId: propertyId))
    }

    func confirmSettlement(escrowId: String, txHash: String) async throws -> REConfirmResponse {
        struct Body: Encodable { let txHash: String }
        return try await api.postEnveloped(
            path: "\(base)/escrow/\(escrowId)/confirm", body: Body(txHash: txHash))
    }
}
