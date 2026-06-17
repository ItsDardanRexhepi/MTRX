import Foundation

// MARK: - Models

struct InsuranceCoverage: Codable, Identifiable {
    var id: String { coverageId }
    let coverageId: String
    let name: String
    let description: String
    let maxCoverage: Double
    let premiumRate: Double
    let riskType: String
}

struct SvcInsurancePolicy: Codable, Identifiable {
    var id: String { policyId }
    let policyId: String
    let coverageName: String
    let amount: Double
    let premium: Double
    let startDate: Date
    let endDate: Date
    let status: String
}

struct SvcInsuranceClaim: Codable, Identifiable {
    var id: String { claimId }
    let claimId: String
    let policyId: String
    let description: String
    let status: String
    let filedAt: Date
    let resolvedAt: Date?
}

// MARK: - Service

@MainActor
final class InsuranceService {

    static let shared = InsuranceService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getCoverageOptions() async throws -> [InsuranceCoverage] {
        try await api.get(path: "/insurance/coverages", queryItems: nil)
    }

    func purchaseCoverage(coverageId: String, amount: String, duration: Int) async throws -> SvcInsurancePolicy {
        try await api.post(path: "/insurance/coverages/\(coverageId)/purchase", body: [
            "amount": amount,
            "duration": String(duration)
        ])
    }

    func getUserPolicies(address: String) async throws -> [SvcInsurancePolicy] {
        try await api.get(path: "/insurance/policies", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func fileClaim(policyId: String, description: String) async throws -> SvcInsuranceClaim {
        try await api.post(path: "/insurance/policies/\(policyId)/claim", body: [
            "description": description
        ])
    }

    func getClaimStatus(claimId: String) async throws -> SvcInsuranceClaim {
        try await api.get(path: "/insurance/claims/\(claimId)", queryItems: nil)
    }
}
