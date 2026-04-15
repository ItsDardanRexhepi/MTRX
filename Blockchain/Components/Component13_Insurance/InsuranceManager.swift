// InsuranceManager.swift
// MTRX Blockchain - Components - Insurance
//
// Parametric insurance: smart contract policies, automated claims, oracle-driven payouts

import Foundation
import Combine

// MARK: - Protocols

protocol InsuranceDelegate: AnyObject {
    func insurance(_ manager: InsuranceManager, policyActivated policy: InsurancePolicy)
    func insurance(_ manager: InsuranceManager, claimTriggered claim: InsuranceClaim)
    func insurance(_ manager: InsuranceManager, payoutExecuted payout: InsurancePayout)
}

// MARK: - Data Models

struct InsurancePolicy: Identifiable, Codable {
    let id: String
    let holderAddress: String
    let type: PolicyType
    let coverageAmount: Double
    let premiumAmount: Double
    let premiumToken: String
    let startDate: Date
    let endDate: Date
    var status: PolicyStatus
    let triggerConditions: [InsuranceTriggerCondition]
    let contractAddress: String?
}

enum PolicyType: String, Codable {
    case weather, flight, crop, health, property, defi, smartContract
}

enum PolicyStatus: String, Codable {
    case pending, active, claimFiled, claimApproved, paidOut, expired, cancelled
}

struct InsuranceTriggerCondition: Codable {
    let parameter: String
    let comparison: ComparisonOp
    let threshold: Double
    let oracleSource: String
}

enum ComparisonOp: String, Codable {
    case greaterThan, lessThan, equalTo, greaterOrEqual, lessOrEqual
}

struct InsuranceClaim: Identifiable, Codable {
    let id: String
    let policyId: String
    let filedAt: Date
    let triggerData: TriggerData
    var status: ClaimStatus
    var reviewNotes: String?
}

struct TriggerData: Codable {
    let parameter: String
    let actualValue: Double
    let threshold: Double
    let oracleTimestamp: Date
    let oracleProof: String
}

enum ClaimStatus: String, Codable {
    case pending, verified, approved, rejected, paidOut
}

struct InsurancePayout: Identifiable, Codable {
    let id: String
    let claimId: String
    let policyId: String
    let amount: Double
    let token: String
    let transactionHash: String?
    let paidAt: Date
}

enum InsuranceError: Error, LocalizedError {
    case policyNotFound(String)
    case policyExpired
    case claimAlreadyFiled
    case conditionNotMet
    case payoutFailed(String)
    case premiumInsufficient

    var errorDescription: String? {
        switch self {
        case .policyNotFound(let id): return "Policy not found: \(id)"
        case .policyExpired: return "Policy has expired."
        case .claimAlreadyFiled: return "A claim has already been filed for this policy."
        case .conditionNotMet: return "Trigger condition not met."
        case .payoutFailed(let r): return "Payout failed: \(r)"
        case .premiumInsufficient: return "Premium amount is insufficient for requested coverage."
        }
    }
}

// MARK: - InsuranceManager

final class InsuranceManager: ObservableObject {

    static let shared = InsuranceManager()

    weak var delegate: InsuranceDelegate?

    @Published private(set) var policies: [InsurancePolicy] = []
    @Published private(set) var claims: [InsuranceClaim] = []
    @Published private(set) var payouts: [InsurancePayout] = []

    private var policyStore: [String: InsurancePolicy] = [:]
    private var claimStore: [String: InsuranceClaim] = [:]

    // MARK: - Policy Management

    func createPolicy(holder: String, type: PolicyType, coverage: Double, premium: Double, premiumToken: String, duration: TimeInterval, conditions: [InsuranceTriggerCondition]) async throws -> InsurancePolicy {
        guard premium >= coverage * 0.001 else {
            throw InsuranceError.premiumInsufficient
        }

        let policy = InsurancePolicy(
            id: UUID().uuidString,
            holderAddress: holder,
            type: type,
            coverageAmount: coverage,
            premiumAmount: premium,
            premiumToken: premiumToken,
            startDate: Date(),
            endDate: Date().addingTimeInterval(duration),
            status: .active,
            triggerConditions: conditions,
            contractAddress: nil
        )

        policyStore[policy.id] = policy
        await MainActor.run {
            policies.append(policy)
        }
        delegate?.insurance(self, policyActivated: policy)
        return policy
    }

    func getPolicy(id: String) -> InsurancePolicy? {
        policyStore[id]
    }

    func getActivePolicies(for holder: String) -> [InsurancePolicy] {
        policyStore.values.filter { $0.holderAddress == holder && $0.status == .active }
    }

    // MARK: - Claims

    func fileClaim(policyId: String, triggerData: TriggerData) async throws -> InsuranceClaim {
        guard var policy = policyStore[policyId] else {
            throw InsuranceError.policyNotFound(policyId)
        }
        guard policy.status == .active else {
            throw InsuranceError.policyExpired
        }
        guard policy.endDate > Date() else {
            throw InsuranceError.policyExpired
        }

        let conditionMet = policy.triggerConditions.contains { condition in
            evaluateCondition(condition, actualValue: triggerData.actualValue)
        }
        guard conditionMet else {
            throw InsuranceError.conditionNotMet
        }

        let claim = InsuranceClaim(
            id: UUID().uuidString,
            policyId: policyId,
            filedAt: Date(),
            triggerData: triggerData,
            status: .verified,
            reviewNotes: nil
        )

        claimStore[claim.id] = claim
        policy.status = .claimFiled
        policyStore[policyId] = policy

        await MainActor.run { claims.append(claim) }
        delegate?.insurance(self, claimTriggered: claim)
        return claim
    }

    // MARK: - Payouts

    func executePayout(claimId: String) async throws -> InsurancePayout {
        guard var claim = claimStore[claimId] else {
            throw InsuranceError.policyNotFound(claimId)
        }
        guard let policy = policyStore[claim.policyId] else {
            throw InsuranceError.policyNotFound(claim.policyId)
        }

        let payout = InsurancePayout(
            id: UUID().uuidString,
            claimId: claimId,
            policyId: policy.id,
            amount: policy.coverageAmount,
            token: policy.premiumToken,
            transactionHash: nil,
            paidAt: Date()
        )

        claim.status = .paidOut
        claimStore[claimId] = claim

        await MainActor.run { payouts.append(payout) }
        delegate?.insurance(self, payoutExecuted: payout)
        return payout
    }

    // MARK: - Oracle Monitoring

    func checkInsuranceTriggerConditions(policyId: String, oracleValue: Double) -> Bool {
        guard let policy = policyStore[policyId] else { return false }
        return policy.triggerConditions.contains { evaluateCondition($0, actualValue: oracleValue) }
    }

    // MARK: - Private

    private func evaluateCondition(_ condition: InsuranceTriggerCondition, actualValue: Double) -> Bool {
        switch condition.comparison {
        case .greaterThan: return actualValue > condition.threshold
        case .lessThan: return actualValue < condition.threshold
        case .equalTo: return abs(actualValue - condition.threshold) < 0.0001
        case .greaterOrEqual: return actualValue >= condition.threshold
        case .lessOrEqual: return actualValue <= condition.threshold
        }
    }
}
