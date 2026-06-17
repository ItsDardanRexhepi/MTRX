import Foundation

// MARK: - Models

enum AlertCondition: String, Codable {
    case above
    case below
}

struct PriceAlert: Codable, Identifiable {
    var id: String { alertId }
    let alertId: String
    let token: String
    let condition: AlertCondition
    let targetPrice: Double
    let currentPrice: Double?
    let createdAt: Date
    let triggeredAt: Date?
}

// MARK: - Service

@MainActor
final class AlertsService {

    static let shared = AlertsService()
    private let api = MTRXAPIClient.shared

    private init() {}

    func getAlerts(address: String) async throws -> [PriceAlert] {
        try await api.get(path: "/alerts", queryItems: [
            URLQueryItem(name: "address", value: address)
        ])
    }

    func createAlert(token: String, condition: AlertCondition, targetPrice: String) async throws -> PriceAlert {
        try await api.post(path: "/alerts", body: [
            "token": token,
            "condition": condition.rawValue,
            "targetPrice": targetPrice
        ])
    }

    func deleteAlert(alertId: String) async throws {
        let _: SvcTransactionResult = try await api.post(path: "/alerts/\(alertId)/delete", body: nil as String?)
    }
}
