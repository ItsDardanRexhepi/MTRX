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

    /// Server endpoint that signs the verifying-paymaster data. The signing key
    /// lives ONLY on this server — never in the app. Injectable for tests.
    private let paymasterSignatureEndpoint: String
    private let entryPoint: String
    private let chainID: Int
    /// URLSession for the paymaster server call (injectable: a MockURLProtocol
    /// session in tests).
    private let paymasterSession: URLSession

    /// Cached ETH/USD spot price. 0 = unknown — we never substitute a fake/stale
    /// price. Refreshed from PendingCredentials.Pricing.ethUsdSource.
    private var cachedEthUsdPrice: Double = 0

    /// Cached Base L1 base fee (wei). 0 = unknown. Pushed from the network layer
    /// (Base GasPriceOracle predeploy) via updateL1BaseFee.
    private var cachedL1BaseFeeWei: UInt64 = 0

    private let sponsorshipQueue = DispatchQueue(label: "com.mtrx.gas.sponsorship", qos: .userInitiated)

    // MARK: - Initialization

    init(
        paymasterAddress: String,
        platformBudgetWei: UInt64,
        paymasterProvider: PaymasterProvider? = nil,
        paymasterSignatureEndpoint: String = PendingCredentials.AccountAbstraction.paymasterSignatureEndpoint,
        entryPoint: String = PendingCredentials.AccountAbstraction.entryPointAddress,
        chainID: Int = PendingCredentials.Network.chainID,
        session: URLSession = .shared
    ) {
        self.paymasterAddress = paymasterAddress
        self.paymasterProvider = paymasterProvider
        self.paymasterSignatureEndpoint = paymasterSignatureEndpoint
        self.entryPoint = entryPoint
        self.chainID = chainID
        self.paymasterSession = session
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
                // Fetch the verifying-paymaster data from the signing SERVER
                // (the only holder of the paymaster key) and attach it. If the
                // server isn't configured/reachable, the op proceeds unsponsored
                // — we never fabricate a paymaster signature.
                Task { [weak self] in
                    guard let self = self else { return }
                    let pmData = await self.fetchPaymasterAndData(for: operation)
                    let sponsoredOp = self.withPaymasterData(pmData, operation: operation)
                    self.sponsorshipQueue.async {
                        self.recordSponsorship(userAddress: userAddress, operation: sponsoredOp)
                        completion(.success(sponsoredOp))
                    }
                }
            }
        }
    }

    /// async wrapper around `sponsorOperation` — attaches the server-signed
    /// paymaster data (or throws if the policy/budget declines).
    func sponsoredOperation(_ operation: UserOperation, userAddress: String, userTier: UserTier) async throws -> UserOperation {
        try await withCheckedThrowingContinuation { continuation in
            sponsorOperation(operation: operation, userAddress: userAddress, userTier: userTier) { result in
                switch result {
                case .success(let op): continuation.resume(returning: op)
                case .failure(let error): continuation.resume(throwing: error)
                }
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

    private func withPaymasterData(_ pmData: Data, operation: UserOperation) -> UserOperation {
        UserOperation(
            sender: operation.sender,
            nonce: operation.nonce,
            initCode: operation.initCode,
            callData: operation.callData,
            callGasLimit: operation.callGasLimit,
            verificationGasLimit: operation.verificationGasLimit,
            preVerificationGas: operation.preVerificationGas,
            maxFeePerGas: operation.maxFeePerGas,
            maxPriorityFeePerGas: operation.maxPriorityFeePerGas,
            paymasterAndData: pmData,
            signature: operation.signature
        )
    }

    private struct PaymasterRequest: Encodable {
        let sender: String
        let nonce: String
        let initCode: String
        let callData: String
        let callGasLimit: String
        let verificationGasLimit: String
        let preVerificationGas: String
        let maxFeePerGas: String
        let maxPriorityFeePerGas: String
        let entryPoint: String
        let chainId: Int
    }

    private struct PaymasterReply: Decodable {
        /// Fully-encoded `paymasterAndData` (0x hex): the server appends the
        /// paymaster address, validity window, and ITS OWN signature. The key
        /// never leaves the server.
        let paymasterAndData: String
    }

    /// Request the verifying-paymaster `paymasterAndData` from the server
    /// signing endpoint. Returns empty Data (operation is unsponsored) when the
    /// endpoint/paymaster isn't configured or the server is unreachable — never
    /// a fabricated signature.
    private func fetchPaymasterAndData(for op: UserOperation) async -> Data {
        guard let endpoint = PendingCredentials.filled(paymasterSignatureEndpoint),
              let url = URL(string: endpoint),
              PendingCredentials.filled(paymasterAddress) != nil else {
            return Data()
        }

        func hexU(_ v: UInt64) -> String { "0x" + String(v, radix: 16) }
        func hexD(_ d: Data) -> String { "0x" + d.map { String(format: "%02x", $0) }.joined() }

        let request = PaymasterRequest(
            sender: op.sender,
            nonce: hexU(op.nonce),
            initCode: hexD(op.initCode),
            callData: hexD(op.callData),
            callGasLimit: hexU(op.callGasLimit),
            verificationGasLimit: hexU(op.verificationGasLimit),
            preVerificationGas: hexU(op.preVerificationGas),
            maxFeePerGas: hexU(op.maxFeePerGas),
            maxPriorityFeePerGas: hexU(op.maxPriorityFeePerGas),
            entryPoint: entryPoint,
            chainId: chainID
        )

        var urlReq = URLRequest(url: url)
        urlReq.httpMethod = "POST"
        urlReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlReq.timeoutInterval = 20
        do {
            urlReq.httpBody = try JSONEncoder().encode(request)
            let (data, response) = try await paymasterSession.data(for: urlReq)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return Data() }
            let reply = try JSONDecoder().decode(PaymasterReply.self, from: data)
            return Self.hexToData(reply.paymasterAndData)
        } catch {
            return Data()
        }
    }

    private static func hexToData(_ hex: String) -> Data {
        var s = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        if s.count % 2 != 0 { s = "0" + s }
        var data = Data(); data.reserveCapacity(s.count / 2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard let byte = UInt8(s[idx..<next], radix: 16) else { return Data() }
            data.append(byte)
            idx = next
        }
        return data
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

    /// Real EVM calldata gas accounting (4 gas per zero byte, 16 per non-zero)
    /// over the L1-posted bytes plus the rollup fixed overhead, multiplied by the
    /// cached Base L1 base fee. Returns 0 when the L1 base fee is unknown — an
    /// honest "unknown", never a guessed fee. The live L1 base fee comes from the
    /// Base GasPriceOracle predeploy (0x420000000000000000000000000000000000000F)
    /// and is pushed in via updateL1BaseFee.
    private func estimateL1DataFee(for operation: UserOperation) -> UInt64 {
        guard cachedL1BaseFeeWei > 0 else { return 0 }
        var bytes = operation.callData
        bytes.append(operation.initCode)
        bytes.append(operation.signature)
        var l1Gas: UInt64 = 0
        for byte in bytes { l1Gas += (byte == 0 ? 4 : 16) }
        l1Gas += 1088   // rollup fixed overhead (Optimism/Base data-fee model)
        return l1Gas &* cachedL1BaseFeeWei
    }

    private func convertWeiToUSD(_ wei: UInt64) -> Double {
        guard cachedEthUsdPrice > 0 else { return 0 }   // unknown → honest 0
        return Double(wei) / 1e18 * cachedEthUsdPrice
    }

    // MARK: - Live pricing inputs (read from config; no hardcoded values)

    /// Refresh ETH/USD from `PendingCredentials.Pricing.ethUsdSource`. An HTTPS
    /// source must return `{ "usd": <number> }`. An on-chain Chainlink aggregator
    /// (0x source) is read by the network layer and pushed via updateEthUsdPrice.
    func refreshEthUsdPrice() async {
        guard let source = PendingCredentials.filled(PendingCredentials.Pricing.ethUsdSource) else { return }
        guard !source.hasPrefix("0x"), let url = URL(string: source) else { return }
        struct PriceReply: Decodable { let usd: Double }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let reply = try? JSONDecoder().decode(PriceReply.self, from: data) else { return }
        cachedEthUsdPrice = reply.usd
    }

    /// Push an ETH/USD price obtained elsewhere (e.g. an on-chain Chainlink read).
    func updateEthUsdPrice(_ price: Double) {
        if price > 0 { cachedEthUsdPrice = price }
    }

    /// Push the current Base L1 base fee (wei) obtained from the GasPriceOracle.
    func updateL1BaseFee(_ wei: UInt64) {
        cachedL1BaseFeeWei = wei
    }
}
