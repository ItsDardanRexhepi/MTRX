import Foundation

// MARK: - Models

struct SvcIPAsset: Codable, Identifiable {
    var id: String { ipId }
    let ipId: String
    let name: String
    let type: String
    let owner: String
    let description: String
    let registeredAt: Date
    let licenseCount: Int
}

struct IPLicense: Codable, Identifiable {
    var id: String { licenseId }
    let licenseId: String
    let ipId: String
    let licensor: String
    let licensee: String
    let scope: String
    let isExclusive: Bool
    let duration: Int
    let price: Double
    let issuedAt: Date
}

struct LicenseTerms: Codable {
    let scope: String
    let isExclusive: Bool
    let durationDays: Int
    let price: Double
    let commercialUse: Bool
}

struct IPRegistrationParams: Codable {
    let owner: String
    let name: String
    let description: String
    let type: String
    let evidenceHash: String?
}

// MARK: - Service

@MainActor
final class LicensingService {

    static let shared = LicensingService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getUserIP(address: String) async throws -> [SvcIPAsset] {
        try await api.get(path: "/api/v1/licensing/ip", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func registerIP(params: IPRegistrationParams) async throws -> SvcIPAsset {
        try await api.post(path: "/api/v1/licensing/ip", body: params)
    }

    func getLicenses(address: String) async throws -> [IPLicense] {
        try await api.get(path: "/api/v1/licensing/licenses", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func issueLicense(ipId: String, recipient: String, terms: LicenseTerms) async throws -> IPLicense {
        struct IssueBody: Codable {
            let ipId: String
            let recipient: String
            let terms: LicenseTerms
        }
        let body = IssueBody(ipId: ipId, recipient: recipient, terms: terms)
        return try await api.post(path: "/api/v1/licensing/licenses", body: body)
    }

    func purchaseLicense(ipId: String, terms: LicenseTerms) async throws -> IPLicense {
        struct PurchaseBody: Codable {
            let ipId: String
            let terms: LicenseTerms
        }
        let body = PurchaseBody(ipId: ipId, terms: terms)
        return try await api.post(path: "/api/v1/licensing/licenses/purchase", body: body)
    }

    func getIPMarketplace() async throws -> [SvcIPAsset] {
        try await api.get(path: "/api/v1/licensing/marketplace")
    }
}
