// SecuritiesManager.swift
// MTRX Blockchain - Components - Securities (C18)
//
// ERC-3643 tokenized securities, 0.25% exchange fee, terms negotiation.

import Foundation
import Combine

// MARK: - Protocols

protocol SecuritiesDelegate: AnyObject {
    func securities(_ manager: SecuritiesManager, tokenIssued token: SecurityTokenERC3643)
    func securities(_ manager: SecuritiesManager, tradeExecuted trade: SecuritiesTrade)
    func securities(_ manager: SecuritiesManager, termsNegotiated terms: TermsNegotiation)
}

// MARK: - Data Models

enum SecurityTokenType: String, Codable {
    case equity, debt, fund, realEstate, revenue, hybrid
}

enum ComplianceStatus: String, Codable {
    case pending, verified, rejected, suspended
}

enum NegotiationStatus: String, Codable {
    case proposed, counterOffer, accepted, rejected, expired
}

/// ERC-3643 compliant security token.
struct SecurityTokenERC3643: Identifiable, Codable {
    let id: String
    let symbol: String
    let name: String
    let issuerAddress: String
    let totalSupply: Double
    let tokenType: SecurityTokenType
    let jurisdiction: String
    let issuedAt: Date
    let contractAddress: String?
    var holders: [String: Double]         // address -> balance
    var complianceRegistry: [String: ComplianceStatus]  // address -> compliance
    let identityRegistryAddress: String?  // ERC-3643 ONCHAINID
    let complianceModuleAddress: String?  // ERC-3643 compliance contract
}

struct SecuritiesTrade: Identifiable, Codable {
    let id: String
    let tokenId: String
    let sellerAddress: String
    let buyerAddress: String
    let amount: Double
    let pricePerToken: Double
    let totalPrice: Double
    let fee: Double              // 0.25%
    let executedAt: Date
    let txHash: String?
}

struct TermsNegotiation: Identifiable, Codable {
    let id: String
    let tokenId: String
    let proposerAddress: String
    let counterpartyAddress: String
    var proposedTerms: [String: String]
    var counterTerms: [String: String]?
    var status: NegotiationStatus
    let createdAt: Date
    var updatedAt: Date
}

enum SecuritiesError: Error, LocalizedError {
    case tokenNotFound(String)
    case complianceCheckFailed(String)
    case insufficientBalance
    case negotiationNotFound(String)
    case negotiationClosed
    case buyerNotCompliant
    case sellerNotCompliant
    case issuanceFailed(String)
    case displayOnly

    var errorDescription: String? {
        switch self {
        case .tokenNotFound(let id): return "Security token not found: \(id)"
        case .complianceCheckFailed(let r): return "Compliance check failed: \(r)"
        case .insufficientBalance: return "Insufficient token balance."
        case .negotiationNotFound(let id): return "Negotiation not found: \(id)"
        case .negotiationClosed: return "Negotiation is no longer open."
        case .buyerNotCompliant: return "Buyer has not passed compliance verification."
        case .sellerNotCompliant: return "Seller has not passed compliance verification."
        case .issuanceFailed(let r): return "Token issuance failed: \(r)"
        case .displayOnly: return "Securities issuance/trading is display-only in this build — no in-app execution."
        }
    }
}

// MARK: - SecuritiesManager
//
// REGULATED COMPONENT — DISPLAY-ONLY.
// Security-token issuance and trading is among the most heavily regulated
// activities (securities law). This build displays tokens, holders and
// compliance status but performs NO in-app execution. issueToken/executeTrade
// refuse with `.displayOnly` rather than fabricating issuance/transfers.
// Gated by FeatureFlags.mvpMode upstream.

final class SecuritiesManager: ObservableObject {

    static let shared = SecuritiesManager()

    /// Exchange fee: 0.25%
    static let exchangeFeeRate: Double = 0.0025

    weak var delegate: SecuritiesDelegate?

    @Published private(set) var tokens: [SecurityTokenERC3643] = []
    @Published private(set) var trades: [SecuritiesTrade] = []
    @Published private(set) var negotiations: [TermsNegotiation] = []
    @Published private(set) var isLoading = false

    private var tokenStore: [String: SecurityTokenERC3643] = [:]
    private var negotiationStore: [String: TermsNegotiation] = [:]

    // MARK: - Token Issuance (ERC-3643)

    /// Issue token — REGULATED display-only: refuses (no in-app execution).
    func issueToken(symbol: String, name: String, issuer: String, totalSupply: Double, tokenType: SecurityTokenType, jurisdiction: String) async throws -> SecurityTokenERC3643 {
        throw SecuritiesError.displayOnly
    }

    // MARK: - Compliance (ERC-3643 Identity Registry)

    func setComplianceStatus(tokenId: String, address: String, status: ComplianceStatus) async throws {
        guard var token = tokenStore[tokenId] else {
            throw SecuritiesError.tokenNotFound(tokenId)
        }
        token.complianceRegistry[address] = status
        tokenStore[tokenId] = token
        await updateTokenInPublished(token)
    }

    func isCompliant(tokenId: String, address: String) -> Bool {
        tokenStore[tokenId]?.complianceRegistry[address] == .verified
    }

    // MARK: - Trading with 0.25% Fee

    /// Execute a trade. Both buyer and seller must be compliance-verified.
    /// Execute trade — REGULATED display-only: refuses (no in-app execution).
    func executeTrade(tokenId: String, seller: String, buyer: String, amount: Double, pricePerToken: Double) async throws -> SecuritiesTrade {
        throw SecuritiesError.displayOnly
    }

    // MARK: - Terms Negotiation

    func proposeTerms(tokenId: String, proposer: String, counterparty: String, terms: [String: String]) async throws -> TermsNegotiation {
        guard tokenStore[tokenId] != nil else {
            throw SecuritiesError.tokenNotFound(tokenId)
        }

        let negotiation = TermsNegotiation(
            id: UUID().uuidString,
            tokenId: tokenId,
            proposerAddress: proposer,
            counterpartyAddress: counterparty,
            proposedTerms: terms,
            counterTerms: nil,
            status: .proposed,
            createdAt: Date(),
            updatedAt: Date()
        )

        negotiationStore[negotiation.id] = negotiation
        await MainActor.run { negotiations.append(negotiation) }
        delegate?.securities(self, termsNegotiated: negotiation)
        return negotiation
    }

    func submitCounterOffer(negotiationId: String, counterTerms: [String: String]) async throws -> TermsNegotiation {
        guard var neg = negotiationStore[negotiationId] else {
            throw SecuritiesError.negotiationNotFound(negotiationId)
        }
        guard neg.status == .proposed || neg.status == .counterOffer else {
            throw SecuritiesError.negotiationClosed
        }

        neg.counterTerms = counterTerms
        neg.status = .counterOffer
        neg.updatedAt = Date()
        negotiationStore[negotiationId] = neg
        await updateNegotiationInPublished(neg)
        return neg
    }

    func acceptTerms(negotiationId: String) async throws -> TermsNegotiation {
        guard var neg = negotiationStore[negotiationId] else {
            throw SecuritiesError.negotiationNotFound(negotiationId)
        }
        guard neg.status == .proposed || neg.status == .counterOffer else {
            throw SecuritiesError.negotiationClosed
        }

        neg.status = .accepted
        neg.updatedAt = Date()
        negotiationStore[negotiationId] = neg
        await updateNegotiationInPublished(neg)
        delegate?.securities(self, termsNegotiated: neg)
        return neg
    }

    func rejectTerms(negotiationId: String) async throws {
        guard var neg = negotiationStore[negotiationId] else {
            throw SecuritiesError.negotiationNotFound(negotiationId)
        }
        neg.status = .rejected
        neg.updatedAt = Date()
        negotiationStore[negotiationId] = neg
        await updateNegotiationInPublished(neg)
    }

    // MARK: - Queries

    func getToken(id: String) -> SecurityTokenERC3643? {
        tokenStore[id]
    }

    func getHoldings(address: String) -> [(token: SecurityTokenERC3643, balance: Double)] {
        tokenStore.values.compactMap { token in
            guard let balance = token.holders[address], balance > 0 else { return nil }
            return (token, balance)
        }
    }

    // MARK: - Private

    @MainActor
    private func updateTokenInPublished(_ token: SecurityTokenERC3643) {
        if let idx = tokens.firstIndex(where: { $0.id == token.id }) {
            tokens[idx] = token
        }
    }

    @MainActor
    private func updateNegotiationInPublished(_ neg: TermsNegotiation) {
        if let idx = negotiations.firstIndex(where: { $0.id == neg.id }) {
            negotiations[idx] = neg
        }
    }
}
