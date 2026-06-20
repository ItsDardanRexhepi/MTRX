// ContractConversion.swift
// MTRX Blockchain - Components - Contract Conversion
//
// Smart contract conversion engine: legal agreements to smart contracts

import Foundation

// MARK: - Protocols

protocol ContractConversionDelegate: AnyObject {
    func conversion(_ engine: ContractConversion, didConvert contractId: String)
    func conversion(_ engine: ContractConversion, didFailWithError error: ContractConversionError)
}

protocol LegalParserProvider {
    func parseAgreement(_ text: String) -> [LegalClause]
    func extractParties(_ text: String) -> [ConversionContractParty]
    func identifyTerms(_ text: String) -> [ContractTerm]
}

// MARK: - Data Models

struct LegalClause {
    let id: String
    let title: String
    let body: String
    let clauseType: ClauseType
    let isConvertible: Bool
    let conditions: [ClauseCondition]
}

enum ClauseType: String {
    case payment, delivery, penalty, termination, arbitration, confidentiality, warranty, indemnity
}

struct ClauseCondition {
    let parameter: String
    let operatorType: ConditionOperator
    let value: String
}

enum ConditionOperator: String {
    case equals, greaterThan, lessThan, before, after, contains
}

struct ConversionContractParty {
    let name: String
    let role: String
    let address: String?
    let walletAddress: String?
}

struct ContractTerm {
    let name: String
    let value: String
    let dataType: String
    let unit: String?
}

struct SmartContractSpec {
    let contractId: String
    let sourceAgreement: String
    let parties: [ConversionContractParty]
    let clauses: [ConvertedClause]
    let deploymentConfig: DeploymentConfig
    let createdAt: Date
    let status: ConversionStatus
}

struct ConvertedClause {
    let originalClauseId: String
    let solidityFunction: String
    let parameters: [String: String]
    let triggers: [String]
    let isAutomatable: Bool
}

struct DeploymentConfig {
    let network: String
    let gasLimit: UInt64
    let constructorArgs: [String]
    let libraries: [String: String]
}

enum ConversionStatus: String {
    case draft, analyzing, converting, review, deployed, failed
}

enum ContractConversionError: Error, LocalizedError {
    case parsingFailed(reason: String)
    case unsupportedClause(clauseType: ClauseType)
    case ambiguousTerms
    case missingParties
    case deploymentFailed(reason: String)
    case validationFailed(issues: [String])

    var errorDescription: String? {
        switch self {
        case .parsingFailed(let r): return "Failed to parse legal agreement: \(r)"
        case .unsupportedClause(let t): return "Unsupported clause type: \(t.rawValue)"
        case .ambiguousTerms: return "Agreement contains ambiguous terms."
        case .missingParties: return "Required contract parties are missing."
        case .deploymentFailed(let r): return "Deployment failed: \(r)"
        case .validationFailed(let issues): return "Validation failed: \(issues.joined(separator: ", "))"
        }
    }
}

// MARK: - ContractConversion

final class ContractConversion {

    // MARK: - Properties

    weak var delegate: ContractConversionDelegate?

    private let legalParser: LegalParserProvider?
    private let erc4337Manager: ERC4337Manager
    private var conversions: [String: SmartContractSpec] = [:]
    private let processingQueue = DispatchQueue(label: "com.mtrx.contract.conversion", qos: .userInitiated)

    // MARK: - Initialization

    init(erc4337Manager: ERC4337Manager, legalParser: LegalParserProvider? = nil) {
        self.erc4337Manager = erc4337Manager
        self.legalParser = legalParser
    }

    // MARK: - Conversion Pipeline

    /// Analyze a legal agreement and produce a conversion plan
    func analyzeAgreement(_ text: String, completion: @escaping (Result<SmartContractSpec, ContractConversionError>) -> Void) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            guard let parser = self.legalParser else {
                completion(.failure(.parsingFailed(reason: "No parser configured")))
                return
            }

            let parties = parser.extractParties(text)
            guard !parties.isEmpty else {
                completion(.failure(.missingParties))
                return
            }

            let clauses = parser.parseAgreement(text)
            let terms = parser.identifyTerms(text)

            let convertedClauses = clauses.compactMap { clause -> ConvertedClause? in
                guard clause.isConvertible else { return nil }
                return self.convertClause(clause, terms: terms)
            }

            let spec = SmartContractSpec(
                contractId: UUID().uuidString,
                sourceAgreement: text,
                parties: parties,
                clauses: convertedClauses,
                deploymentConfig: DeploymentConfig(
                    network: "base",
                    gasLimit: 3_000_000,
                    constructorArgs: parties.compactMap { $0.walletAddress },
                    libraries: [:]
                ),
                createdAt: Date(),
                status: .analyzing
            )

            self.conversions[spec.contractId] = spec
            completion(.success(spec))
        }
    }

    /// Convert the analyzed agreement into a deployable smart contract
    func convertToSmartContract(contractId: String, completion: @escaping (Result<SmartContractSpec, ContractConversionError>) -> Void) {
        guard var spec = conversions[contractId] else {
            completion(.failure(.parsingFailed(reason: "Contract not found")))
            return
        }

        // Validate all clauses
        let issues = validateConversion(spec)
        guard issues.isEmpty else {
            completion(.failure(.validationFailed(issues: issues)))
            return
        }

        spec = SmartContractSpec(
            contractId: spec.contractId,
            sourceAgreement: spec.sourceAgreement,
            parties: spec.parties,
            clauses: spec.clauses,
            deploymentConfig: spec.deploymentConfig,
            createdAt: spec.createdAt,
            status: .converting
        )
        conversions[contractId] = spec
        delegate?.conversion(self, didConvert: contractId)
        completion(.success(spec))
    }

    /// Deploy the converted smart contract on-chain.
    ///
    /// Bridges the completion API to the real on-chain `deployOnChain` path:
    /// enclave-signed UserOp → server paymaster → bundler, via the CREATE2 factory
    /// at PendingCredentials.Components.contractConversion. `sender` is the user's
    /// smart-account address and `signingKeyTag` their Secure Enclave key tag; both
    /// must be supplied for a real, user-signed deploy (the server never signs).
    ///
    /// HONEST BOUNDARY — Solidity compilation (UNVERIFIED): the app has no in-app
    /// Solidity compiler, so the contract's creation `bytecode` is an INPUT here.
    /// The caller compiles the converted source out of band (e.g. via solc / a build
    /// service) and passes the resulting creation code. We ABI-encode the CREATE2
    /// `deploy(bytes32,bytes)` call around that bytecode and route it through the
    /// real submit pipeline — we never compile, and never fabricate a deploy.
    ///
    /// `salt` makes the CREATE2 address deterministic; when omitted it is derived
    /// from the contractId so re-deploys of the same spec target the same address.
    ///
    /// GRACEFUL CONFIG: when the chain core is unconfigured, `WalletTransactionService.init?`
    /// returns nil and we surface a clear "needs config" error; when the factory
    /// address is blank, `deployOnChain` throws the same — never a stub, never a
    /// fake success, never a fabricated tx hash.
    ///
    /// HONEST RESULT: the *deployed* contract address is only known once the factory
    /// tx is mined (read it from the UserOperation receipt's Deployed log) — we never
    /// invent it here. On success this reports the real bundler `userOpHash`; the
    /// caller resolves the on-chain address from the receipt.
    func deployContract(
        contractId: String,
        bytecode: Data,
        sender: String,
        signingKeyTag: String,
        salt: Data? = nil,
        completion: @escaping (Result<String, ContractConversionError>) -> Void
    ) {
        guard let spec = conversions[contractId] else {
            completion(.failure(.parsingFailed(reason: "Contract not found")))
            return
        }
        guard !bytecode.isEmpty else {
            completion(.failure(.deploymentFailed(reason: "No compiled bytecode supplied — Solidity compilation is performed out of band (no in-app compiler)")))
            return
        }
        // Deterministic CREATE2 salt: caller-supplied, else derived from the spec id
        // so the counterfactual address is stable across re-deploys of this contract.
        let create2Salt = salt ?? Data(spec.contractId.utf8)

        Task { @MainActor in
            // Gate on the chain core: nil until PendingCredentials (rpc/bundler/chain)
            // are filled. WalletTransactionService.init? is @MainActor. Never a fake deploy.
            guard let service = WalletTransactionService() else {
                completion(.failure(.deploymentFailed(reason: "On-chain config not set — fill PendingCredentials (chain core + ContractConversion factory)")))
                return
            }
            do {
                let submission = try await self.deployOnChain(
                    salt: create2Salt,
                    bytecode: bytecode,
                    sender: sender,
                    signingKeyTag: signingKeyTag,
                    service: service
                )
                // Mark the local spec as deployed only after the submit pipeline
                // returns a real userOpHash. The on-chain address is resolved from
                // the receipt by the caller — not invented here.
                self.conversions[contractId] = SmartContractSpec(
                    contractId: spec.contractId,
                    sourceAgreement: spec.sourceAgreement,
                    parties: spec.parties,
                    clauses: spec.clauses,
                    deploymentConfig: spec.deploymentConfig,
                    createdAt: spec.createdAt,
                    status: .deployed
                )
                self.delegate?.conversion(self, didConvert: contractId)
                completion(.success(submission.userOpHash))
            } catch {
                completion(.failure(.deploymentFailed(reason: error.localizedDescription)))
            }
        }
    }

    // MARK: - On-chain execution (via the submit pipeline)

    /// ABI-encode `deploy(bytes32 salt, bytes bytecode)` (CREATE2 factory).
    /// `bytecode` is the already-compiled contract creation code — compilation
    /// itself is out of scope for the app (no in-app Solidity compiler).
    static func encodeDeploy(salt: Data, bytecode: Data) -> Data {
        var saltWord = Data(repeating: 0, count: 32)
        let head = salt.prefix(32)
        saltWord.replaceSubrange(0..<head.count, with: head)
        var out = ABIEncoder.functionSelector("deploy(bytes32,bytes)")
        out.append(saltWord)
        out.append(ABIEncoder.encodeOffset(64)) // bytes arg follows 2 head words
        out.append(ABIEncoder.encodeBytes(bytecode))
        return out
    }

    /// Deploy compiled bytecode through the real submit pipeline: enclave-signed
    /// UserOp → server paymaster → bundler. Factory address deferred to
    /// PendingCredentials (nil until set → throws, never a fake deploy).
    @MainActor
    func deployOnChain(
        salt: Data,
        bytecode: Data,
        sender: String,
        signingKeyTag: String,
        service: WalletTransactionService,
        contract: String? = PendingCredentials.filled(PendingCredentials.Components.contractConversion)
    ) async throws -> WalletTransactionService.Submission {
        guard let factory = contract else {
            throw ContractConversionError.deploymentFailed(reason: "ContractConversion factory not configured (PendingCredentials.Components.contractConversion)")
        }
        return try await service.submitCall(
            to: factory,
            value: 0,
            data: Self.encodeDeploy(salt: salt, bytecode: bytecode),
            sender: sender,
            signingKeyTag: signingKeyTag
        )
    }

    // MARK: - Private Helpers

    private func convertClause(_ clause: LegalClause, terms: [ContractTerm]) -> ConvertedClause {
        let functionName = "execute\(clause.title.replacingOccurrences(of: " ", with: ""))"
        let params = clause.conditions.reduce(into: [String: String]()) { result, condition in
            result[condition.parameter] = condition.value
        }
        return ConvertedClause(
            originalClauseId: clause.id,
            solidityFunction: functionName,
            parameters: params,
            triggers: clause.conditions.map { $0.parameter },
            isAutomatable: clause.clauseType == .payment || clause.clauseType == .delivery
        )
    }

    private func validateConversion(_ spec: SmartContractSpec) -> [String] {
        var issues: [String] = []
        if spec.parties.contains(where: { $0.walletAddress == nil }) {
            issues.append("All parties must have wallet addresses.")
        }
        if spec.clauses.isEmpty {
            issues.append("No convertible clauses found.")
        }
        return issues
    }
}
