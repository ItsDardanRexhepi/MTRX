import Foundation

// MARK: - Models

struct SvcDisputeCase: Codable, Identifiable {
    var id: String { disputeId }
    let disputeId: String
    let creator: String
    let respondent: String
    let description: String
    let status: String
    let stake: Double
    let votesFor: Int
    let votesAgainst: Int
    let deadline: Date
}

struct DisputeParams: Codable {
    let respondent: String
    let description: String
    let stake: Double
}

// MARK: - Service

@MainActor
final class DisputeService {

    static let shared = DisputeService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func createDispute(params: DisputeParams) async throws -> SvcDisputeCase {
        try await api.post(path: "/disputes", body: params)
    }

    func getDisputes(address: String) async throws -> [SvcDisputeCase] {
        try await api.get(path: "/disputes", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getOpenJuryCases() async throws -> [SvcDisputeCase] {
        try await api.get(path: "/disputes/jury", queryItems: nil)
    }

    func submitVote(disputeId: String, ruling: Int) async throws -> SvcTransactionResult {
        try await api.post(path: "/disputes/\(disputeId)/vote", body: ["ruling": String(ruling)])
    }

    func claimReward(disputeId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/disputes/\(disputeId)/claim-reward", body: nil as String?)
    }
}
