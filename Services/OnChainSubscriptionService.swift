import Foundation

// MARK: - Models

struct OnChainSubscription: Codable, Identifiable {
    var id: String { subscriptionId }
    let subscriptionId: String
    let service: String
    let tier: String
    let price: Double
    let token: String
    let nextBillingDate: Date
    let status: String
}

struct SubscriptionOffering: Codable, Identifiable {
    var id: String { offeringId }
    let offeringId: String
    let name: String
    let description: String
    let tiers: [OfferingTier]
}

struct OfferingTier: Codable, Identifiable {
    let id: UUID
    let name: String
    let price: Double
    let token: String
    let features: [String]
}

struct SubscriptionOfferingParams: Codable {
    let name: String
    let description: String
    let tiers: [OfferingTier]
}

struct SubscriptionRevenue: Codable {
    let totalMRR: Double
    let subscriberCount: Int
    let plans: [PlanBreakdown]
}

struct PlanBreakdown: Codable, Identifiable {
    let id: UUID
    let tier: String
    let subscribers: Int
    let revenue: Double
}

// MARK: - Service

@MainActor
final class OnChainSubscriptionService {

    static let shared = OnChainSubscriptionService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getUserSubscriptions(address: String) async throws -> [OnChainSubscription] {
        try await api.get(path: "/subscriptions", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func getSubscriptionOfferings() async throws -> [SubscriptionOffering] {
        try await api.get(path: "/subscriptions/offerings")
    }

    func subscribe(offeringId: String, tierId: String) async throws -> OnChainSubscription {
        try await api.post(path: "/subscriptions", body: [
            "offeringId": offeringId,
            "tierId": tierId
        ])
    }

    func cancelSubscription(subscriptionId: String) async throws -> SvcTransactionResult {
        try await api.post(path: "/subscriptions/\(subscriptionId)/cancel", body: nil as String?)
    }

    func createOffering(params: SubscriptionOfferingParams) async throws -> SubscriptionOffering {
        try await api.post(path: "/subscriptions/offerings", body: params)
    }

    func getSubscriberRevenue(address: String) async throws -> SubscriptionRevenue {
        try await api.get(path: "/subscriptions/revenue", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }
}
