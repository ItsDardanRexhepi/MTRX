// GasSponsorship.swift
// MTRX Blockchain - Wallet
//
// Platform covers gas for users via paymaster integration

import Foundation

// MARK: - Protocols

protocol GasSponsorshipDelegate: AnyObject {
    func sponsorship(_ sponsorship: GasSponsorship, didSponsorOperation operationHash: String, gasUsed: UInt64)
    func sponsorship(_ sponsorship: GasSponsorship, didRejectOperation reason: SponsorshipRejectionReason)
    func sponsorship(_ sponsorship: GasSponsorship, budgetWarning remaining: Double)
}

protocol PaymasterProvider {
    func sponsorUserOperation(_ operation: UserOperation, policy: SponsorshipPolicy) async throws -> PaymasterResponse
    func validatePaymasterData(for operation: UserOperation) async throws -> Bool
}

// MARK: - Data Models

struct SponsorshipPolicy: Codable {
    let policyId: String
    let name: String
    let maxGasPerOperation: UInt64
    let maxOperationsPerDay: Int
    let maxDailySpendWei: UInt64
    let allowedContracts: [String]?
    let allowedMethods: [String]?
    let userTier: UserTier
    var isActive: Bool
}

enum UserTier: String, Codable {
    case free = "free"
    case basic = "basic"
    case premium = "premium"
    case enterprise = "enterprise"

    var dailyGasLimit: UInt64 {
        switch self {
        case .free: return 500_000
        case .basic: return 2_000_000
        case .premium: return 10_000_000
        case .enterprise: return 50_000_000
        }
    }

    var maxOperationsPerDay: Int {
        switch self {
        case .free: return 5
        case .basic: return 25
        case .premium: return 100
        case .enterprise: return 500
        }
    }
}

struct PaymasterResponse {
    let paymasterAndData: Data
    let preVerificationGas: UInt64
    let verificationGasLimit: UInt64
    let callGasLimit: UInt64
}

struct GasEstimate {
    let totalGasWei: UInt64
    let gasPrice: UInt64
    let estimatedCostUSD: Double
    let l1DataFee: UInt64
    let l2ExecutionFee: UInt64
}

struct SponsorshipBudget {
    let totalBudgetWei: UInt64
    let spentWei: UInt64
    let remainingWei: UInt64
    let periodStart: Date
    let periodEnd: Date
    let operationCount: Int

    var utilizationPercent: Double {
        guard totalBudgetWei > 0 else { return 0 }
        return Double(spentWei) / Double(totalBudgetWei) * 100.0
    }
}

enum SponsorshipRejectionReason {
    case dailyLimitExceeded
    case operationLimitExceeded
    case contractNotAllowed
    case methodNotAllowed
    case budgetExhausted
    case policyInactive
    case userSuspended
    case estimationFailed
}

enum GasSponsorshipError: Error, LocalizedError {
    case policyNotFound
    case budgetExhausted
    case estimationFailed(reason: String)
    case paymasterError(reason: String)
    case invalidOperation
    case sponsorshipDenied(reason: SponsorshipRejectionReason)

    var errorDescription: String? {
        switch self {
        case .policyNotFound: return "No sponsorship policy found for this user."
        case .budgetExhausted: return "Sponsorship budget has been exhausted."
        case .estimationFailed(let reason): return "Gas estimation failed: \(reason)"
        case .paymasterError(let reason): return "Paymaster error: \(reason)"
        case .invalidOperation: return "Invalid UserOperation for sponsorship."
        case .sponsorshipDenied(let reason): return "Sponsorship denied: \(reason)"
        }
    }
}

// MARK: - GasSponsorship

final class GasSponsorship {

    // MARK: - Properties

    weak var delegate: GasSponsorshipDelegate?

    /// Paymaster contract address
    let paymasterAddress: String

    /// Active sponsorship policies
    private var policies: [String: SponsorshipPolicy] = [:]

    /// Budget tracking per user
    private var userBudgets: [String: SponsorshipBudget] = [:]

    /// Daily operation counts per user
    private var dailyOperationCounts: [String: Int] = [:]

    /// Global platform budget
    private var platformBudget: SponsorshipBudget

    /// Budget warning threshold (percentage)
    private let budgetWarningThreshold: Double = 80.0

    /// Paymaster provider for on-chain interactions
    private let paymasterProvider: PaymasterProvider?

    private let sponsorshipQueue = DispatchQueue(label: "com.mtrx.gas.sponsorship", qos: .userInitiated)

    // MARK: - Initialization

    init(
        paymasterAddress: String,
        platformBudgetWei: UInt64,
        paymasterProvider: PaymasterProvider? = nil
    ) {
        self.paymasterAddress = paymasterAddress
        self.paymasterProvider = paymasterProvider
        self.platformBudget = SponsorshipBudget(
            totalBudgetWei: platformBudgetWei,
            spentWei: 0,
            remainingWei: platformBudgetWei,
            periodStart: Date(),
            periodEnd: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date(),
            operationCount: 0
        )

        setupDefaultPolicies()
    }

    // MARK: - Sponsorship Evaluation

    /// Evaluate whether an operation qualifies for gas sponsorship
    func evaluateSponsorship(
        operation: UserOperation,
        userAddress: String,
        userTier: UserTier
    ) -> Result<SponsorshipPolicy, GasSponsorshipError> {
        // Find applicable policy
        guard let policy = findPolicy(for: userTier) else {
            return .failure(.policyNotFound)
        }

        guard policy.isActive else {
            return .failure(.sponsorshipDenied(reason: .policyInactive))
        }

        // Check daily operation limit
        let dailyCount = dailyOperationCounts[userAddress] ?? 0
        guard dailyCount < policy.maxOperationsPerDay else {
            delegate?.sponsorship(self, didRejectOperation: .operationLimitExceeded)
            return .failure(.sponsorshipDenied(reason: .operationLimitExceeded))
        }

        // Check gas limit
        let totalGas = operation.callGasLimit + operation.verificationGasLimit + operation.preVerificationGas
        guard totalGas <= policy.maxGasPerOperation else {
            delegate?.sponsorship(self, didRejectOperation: .dailyLimitExceeded)
            return .failure(.sponsorshipDenied(reason: .dailyLimitExceeded))
        }

        // Check allowed contracts
        if let allowed = policy.allowedContracts {
            guard allowed.contains(operation.sender) else {
                delegate?.sponsorship(self, didRejectOperation: .contractNotAllowed)
                return .failure(.sponsorshipDenied(reason: .contractNotAllowed))
            }
        }

        // Check platform budget
        guard platformBudget.remainingWei > 0 else {
            delegate?.sponsorship(self, didRejectOperation: .budgetExhausted)
            return .failure(.budgetExhausted)
        }

        return .success(policy)
    }

    /// Sponsor a UserOperation by attaching paymaster data
    func sponsorOperation(
        operation: UserOperation,
        userAddress: String,
        userTier: UserTier,
        completion: @escaping (Result<UserOperation, GasSponsorshipError>) -> Void
    ) {
        sponsorshipQueue.async { [weak self] in
            guard let self = self else { return }

            // Evaluate eligibility
            let evalResult = self.evaluateSponsorship(
                operation: operation,
                userAddress: userAddress,
                userTier: userTier
            )

            switch evalResult {
            case .failure(let error):
                completion(.failure(error))
            case .success:
                // Attach paymaster data to operation
                let sponsoredOp = self.attachPaymasterData(to: operation)
                self.recordSponsorship(userAddress: userAddress, operation: sponsoredOp)
                completion(.success(sponsoredOp))
            }
        }
    }

    // MARK: - Gas Estimation

    /// Estimate gas cost for a UserOperation on Base L2
    func estimateGas(for operation: UserOperation) -> GasEstimate {
        let l2ExecutionFee = (operation.callGasLimit + operation.verificationGasLimit) * operation.maxFeePerGas
        let l1DataFee = estimateL1DataFee(for: operation)
        let totalGasWei = l2ExecutionFee + l1DataFee
        let estimatedCostUSD = convertWeiToUSD(totalGasWei)

        return GasEstimate(
            totalGasWei: totalGasWei,
            gasPrice: operation.maxFeePerGas,
            estimatedCostUSD: estimatedCostUSD,
            l1DataFee: l1DataFee,
            l2ExecutionFee: l2ExecutionFee
        )
    }

    // MARK: - Budget Management

    /// Get the current budget for a user
    func getBudget(for userAddress: String) -> SponsorshipBudget? {
        return userBudgets[userAddress]
    }

    /// Get the platform-wide budget status
    func getPlatformBudget() -> SponsorshipBudget {
        return platformBudget
    }

    /// Reset daily operation counters (call at midnight)
    func resetDailyCounters() {
        dailyOperationCounts.removeAll()
    }

    /// Update the platform budget
    func updatePlatformBudget(totalWei: UInt64) {
        platformBudget = SponsorshipBudget(
            totalBudgetWei: totalWei,
            spentWei: platformBudget.spentWei,
            remainingWei: totalWei > platformBudget.spentWei ? totalWei - platformBudget.spentWei : 0,
            periodStart: platformBudget.periodStart,
            periodEnd: platformBudget.periodEnd,
            operationCount: platformBudget.operationCount
        )
    }

    // MARK: - Policy Management

    /// Register a new sponsorship policy
    func registerPolicy(_ policy: SponsorshipPolicy) {
        policies[policy.policyId] = policy
    }

    /// Deactivate a policy
    func deactivatePolicy(policyId: String) {
        policies[policyId]?.isActive = false
    }

    /// Get all active policies
    func getActivePolicies() -> [SponsorshipPolicy] {
        return policies.values.filter { $0.isActive }
    }

    // MARK: - Private Helpers

    private func setupDefaultPolicies() {
        let freePolicy = SponsorshipPolicy(
            policyId: "default_free",
            name: "Free Tier Gas Sponsorship",
            maxGasPerOperation: 500_000,
            maxOperationsPerDay: 5,
            maxDailySpendWei: 500_000_000,
            allowedContracts: nil,
            allowedMethods: nil,
            userTier: .free,
            isActive: true
        )

        let premiumPolicy = SponsorshipPolicy(
            policyId: "default_premium",
            name: "Premium Tier Gas Sponsorship",
            maxGasPerOperation: 2_000_000,
            maxOperationsPerDay: 100,
            maxDailySpendWei: 10_000_000_000,
            allowedContracts: nil,
            allowedMethods: nil,
            userTier: .premium,
            isActive: true
        )

        policies[freePolicy.policyId] = freePolicy
        policies[premiumPolicy.policyId] = premiumPolicy
    }

    private func findPolicy(for tier: UserTier) -> SponsorshipPolicy? {
        return policies.values.first { $0.userTier == tier && $0.isActive }
    }

    private func attachPaymasterData(to operation: UserOperation) -> UserOperation {
        // TODO: Construct paymaster data with signature from verifying paymaster
        return UserOperation(
            sender: operation.sender,
            nonce: operation.nonce,
            initCode: operation.initCode,
            callData: operation.callData,
            callGasLimit: operation.callGasLimit,
            verificationGasLimit: operation.verificationGasLimit,
            preVerificationGas: operation.preVerificationGas,
            maxFeePerGas: operation.maxFeePerGas,
            maxPriorityFeePerGas: operation.maxPriorityFeePerGas,
            paymasterAndData: buildPaymasterAndData(),
            signature: operation.signature
        )
    }

    private func buildPaymasterAndData() -> Data {
        // TODO: Encode paymaster address + valid until + valid after + signature
        return Data()
    }

    private func recordSponsorship(userAddress: String, operation: UserOperation) {
        let gasUsed = operation.callGasLimit + operation.verificationGasLimit + operation.preVerificationGas
        let costWei = gasUsed * operation.maxFeePerGas

        // Update daily counts
        dailyOperationCounts[userAddress] = (dailyOperationCounts[userAddress] ?? 0) + 1

        // Update platform budget
        platformBudget = SponsorshipBudget(
            totalBudgetWei: platformBudget.totalBudgetWei,
            spentWei: platformBudget.spentWei + costWei,
            remainingWei: platformBudget.remainingWei > costWei ? platformBudget.remainingWei - costWei : 0,
            periodStart: platformBudget.periodStart,
            periodEnd: platformBudget.periodEnd,
            operationCount: platformBudget.operationCount + 1
        )

        // Check budget warning
        if platformBudget.utilizationPercent >= budgetWarningThreshold {
            delegate?.sponsorship(self, budgetWarning: 100.0 - platformBudget.utilizationPercent)
        }

        delegate?.sponsorship(self, didSponsorOperation: operation.hash, gasUsed: gasUsed)
    }

    private func estimateL1DataFee(for operation: UserOperation) -> UInt64 {
        // TODO: Estimate L1 data posting cost for Base rollup
        // Based on calldata size and current L1 gas price
        return UInt64(operation.callData.count) * 16
    }

    private func convertWeiToUSD(_ wei: UInt64) -> Double {
        // TODO: Use oracle price feed for ETH/USD conversion
        let ethPrice = 3000.0
        return Double(wei) / 1e18 * ethPrice
    }
}
