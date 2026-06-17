import Foundation

// MARK: - Models

struct TokenLaunch: Codable, Identifiable {
    var id: String { launchId }
    let launchId: String
    let name: String
    let symbol: String
    let totalSupply: Double
    let price: Double
    let raised: Double
    let participants: Int
    let deadline: Date
    let status: String
}

struct TokenLaunchParams: Codable {
    let name: String
    let symbol: String
    let totalSupply: Double
    let price: Double
    let duration: Int
}

struct VestingSchedule: Codable, Identifiable {
    var id: String { scheduleId }
    let scheduleId: String
    let token: String
    let total: Double
    let claimed: Double
    let claimable: Double
    let nextCliff: Date?
    let linearEnd: Date?
}

struct AirdropRecipient: Codable {
    let address: String
    let amount: Double
}

private struct AirdropBody: Codable {
    let token: String
    let recipients: [AirdropRecipient]
}

// MARK: - Service

@MainActor
final class LaunchService {

    static let shared = LaunchService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func createLaunch(params: TokenLaunchParams) async throws -> TokenLaunch {
        try await api.post(path: "/launch/tokens", body: params)
    }

    func getActiveLaunches() async throws -> [TokenLaunch] {
        try await api.get(path: "/launch/tokens", queryItems: [
            URLQueryItem(name: "status", value: "active")
        ])
    }

    func participateInLaunch(launchId: String, amount: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/launch/tokens/\(launchId)/participate", body: ["amount": amount])
    }

    func getUserLaunches(address: String) async throws -> [TokenLaunch] {
        try await api.get(path: "/launch/tokens", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getVestingSchedule(address: String) async throws -> [VestingSchedule] {
        try await api.get(path: "/launch/vesting", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func claimVested(scheduleId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/launch/vesting/\(scheduleId)/claim", body: nil as String?)
    }

    func distributeAirdrop(token: String, recipients: [AirdropRecipient]) async throws -> SvcTransactionResult {
        let body = AirdropBody(token: token, recipients: recipients)
        return try await api.post(path: "/launch/airdrop", body: body)
    }
}
