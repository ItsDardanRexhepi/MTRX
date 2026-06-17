import Foundation

// MARK: - Models

struct ContractABI: Codable {
    let address: String
    let name: String?
    let functions: [ABIFunction]
    let isVerified: Bool
}

struct ABIFunction: Codable, Identifiable {
    let id: UUID
    let name: String
    let inputs: [ABIParam]
    let outputs: [ABIParam]
    let stateMutability: String
}

struct ABIParam: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: String
    let displayValue: String?
}

struct SvcContractResult: Codable {
    let name: String
    let value: String
    let type: String
    let displayValue: String
}

struct ContractTemplate: Codable, Identifiable {
    var id: String { templateId }
    let templateId: String
    let name: String
    let description: String
    let category: String
    let params: [TemplateParam]
}

struct TemplateParam: Codable, Identifiable {
    let id: UUID
    let name: String
    let type: String
    let description: String
    let defaultValue: String?
}

struct DeploymentEstimate: Codable {
    let gasEstimateUSD: Double
    let deploymentTime: String
}

struct DeploymentResult: Codable {
    let contractAddress: String
    let txHash: String
    let deployedAt: Date
    let templateName: String
}

// MARK: - Service

@MainActor
final class ContractService {

    static let shared = ContractService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getContractABI(address: String) async throws -> ContractABI {
        try await api.get(path: "/contracts/\(address)/abi")
    }

    func readFunction(contract: String, function: String, params: [String]) async throws -> [SvcContractResult] {
        struct ReadBody: Codable {
            let function: String
            let params: [String]
        }
        let body = ReadBody(function: function, params: params)
        return try await api.post(path: "/contracts/\(contract)/read", body: body)
    }

    func writeFunction(contract: String, function: String, params: [String]) async throws -> SvcTransactionResult {
        struct WriteBody: Codable {
            let function: String
            let params: [String]
        }
        let body = WriteBody(function: function, params: params)
        return try await api.post(path: "/contracts/\(contract)/write", body: body)
    }

    func getTemplates() async throws -> [ContractTemplate] {
        try await api.get(path: "/contracts/templates")
    }

    func estimateDeployment(templateId: String, params: [String: String]) async throws -> DeploymentEstimate {
        struct EstimateBody: Codable {
            let templateId: String
            let params: [String: String]
        }
        let body = EstimateBody(templateId: templateId, params: params)
        return try await api.post(path: "/contracts/deploy/estimate", body: body)
    }

    func deployContract(templateId: String, params: [String: String]) async throws -> DeploymentResult {
        struct DeployBody: Codable {
            let templateId: String
            let params: [String: String]
        }
        let body = DeployBody(templateId: templateId, params: params)
        return try await api.post(path: "/contracts/deploy", body: body)
    }
}
