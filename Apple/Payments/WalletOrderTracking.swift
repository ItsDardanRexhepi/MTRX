import PassKit

/// Component 12 supply chain asset tracking in Apple Wallet
final class WalletOrderTracking {
    /// Add supply chain order to Apple Wallet for tracking
    func addOrder(orderId: String, description: String, merchant: String, status: OrderStatus) async throws -> PKPass {
        let orderData = buildOrderPayload(orderId: orderId, description: description, merchant: merchant, status: status)
        guard let pass = try? PKPass(data: orderData) else {
            throw TrackingError.invalidPassData
        }
        let library = PKPassLibrary()
        guard !library.containsPass(pass) else { return pass }
        library.addPasses([pass]) { status in }
        return pass
    }

    func updateOrderStatus(orderId: String, newStatus: OrderStatus) {
        NotificationCenter.default.post(name: .orderStatusUpdated, object: ["orderId": orderId, "status": newStatus.rawValue])
    }

    private func buildOrderPayload(orderId: String, description: String, merchant: String, status: OrderStatus) -> Data {
        let payload: [String: Any] = [
            "orderIdentifier": orderId,
            "orderType": "ecommerce",
            "status": status.rawValue,
            "merchant": ["displayName": merchant],
            "orderManagementURL": "https://openmatrix-ai.com/orders/\(orderId)",
            "lineItems": [["title": description]]
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    enum OrderStatus: String { case placed, shipped, inTransit, delivered, transferred }
    enum TrackingError: Error { case invalidPassData }
}

extension Notification.Name {
    static let orderStatusUpdated = Notification.Name("orderStatusUpdated")
}
