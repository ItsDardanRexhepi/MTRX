// PushKitHandler.swift
// MTRX Apple Integration — Presence
// PushKit for zero-latency urgent alerts (VoIP-style delivery)

import PushKit
import Foundation

// MARK: - PushKit Handler

final class PushKitHandler: NSObject {

    // MARK: - Shared Instance

    static let shared = PushKitHandler()

    // MARK: - Properties

    private var voipRegistry: PKPushRegistry?
    private var onTokenUpdate: ((Data) -> Void)?
    private var onPushReceived: ((PushKitPayload) -> Void)?

    // MARK: - Registration

    /// Registers for VoIP push notifications for zero-latency delivery.
    func register(onToken: @escaping (Data) -> Void, onPush: @escaping (PushKitPayload) -> Void) {
        self.onTokenUpdate = onToken
        self.onPushReceived = onPush

        voipRegistry = PKPushRegistry(queue: .main)
        voipRegistry?.delegate = self
        voipRegistry?.desiredPushTypes = [.voIP]
    }

    /// Unregisters from VoIP push notifications.
    func unregister() {
        voipRegistry?.desiredPushTypes = nil
        voipRegistry?.delegate = nil
        voipRegistry = nil
        onTokenUpdate = nil
        onPushReceived = nil
    }

    // MARK: - Token

    /// Returns the current push token as a hex string if available.
    var currentToken: String? {
        guard let token = voipRegistry?.pushToken(for: .voIP) else { return nil }
        return token.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - PKPushRegistryDelegate

extension PushKitHandler: PKPushRegistryDelegate {

    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        onTokenUpdate?(pushCredentials.token)

        // Register token with MTRX backend
        Task {
            try? await MTRXPushAPI.shared.registerVoIPToken(pushCredentials.token)
        }
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else {
            completion()
            return
        }

        let pushPayload = PushKitPayload(dictionary: payload.dictionaryPayload)

        switch pushPayload.alertType {
        case .liquidation:
            handleLiquidationAlert(pushPayload)
        case .securityBreach:
            handleSecurityAlert(pushPayload)
        case .contractUrgent:
            handleContractAlert(pushPayload)
        case .priceAlert:
            handlePriceAlert(pushPayload)
        case .disputeEscalation:
            handleDisputeAlert(pushPayload)
        case .unknown:
            break
        }

        onPushReceived?(pushPayload)
        completion()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        Task {
            try? await MTRXPushAPI.shared.invalidateVoIPToken()
        }
    }

    // MARK: - Alert Handlers

    private func handleLiquidationAlert(_ payload: PushKitPayload) {
        HapticsManager.shared.playTransactionHaptic(.alertUrgent)

        Task {
            try? await NotificationManager.shared.scheduleCriticalAlert(
                id: payload.alertId,
                title: "Liquidation Warning",
                body: payload.message,
                category: .liquidation
            )
        }
    }

    private func handleSecurityAlert(_ payload: PushKitPayload) {
        HapticsManager.shared.playTransactionHaptic(.alertUrgent)

        Task {
            try? await NotificationManager.shared.scheduleCriticalAlert(
                id: payload.alertId,
                title: "Security Alert",
                body: payload.message,
                category: .security
            )
        }
    }

    private func handleContractAlert(_ payload: PushKitPayload) {
        Task {
            try? await NotificationManager.shared.scheduleTimeSensitive(
                id: payload.alertId,
                title: "Contract Alert",
                body: payload.message,
                category: .contract
            )
        }
    }

    private func handlePriceAlert(_ payload: PushKitPayload) {
        Task {
            try? await NotificationManager.shared.scheduleTimeSensitive(
                id: payload.alertId,
                title: "Price Alert",
                body: payload.message,
                category: .price
            )
        }
    }

    private func handleDisputeAlert(_ payload: PushKitPayload) {
        Task {
            try? await NotificationManager.shared.scheduleCriticalAlert(
                id: payload.alertId,
                title: "Dispute Escalation",
                body: payload.message,
                category: .contract
            )
        }
    }
}

// MARK: - PushKit Payload

struct PushKitPayload {
    let alertId: String
    let alertType: AlertType
    let message: String
    let data: [String: Any]
    let timestamp: Date

    enum AlertType: String {
        case liquidation
        case securityBreach = "security_breach"
        case contractUrgent = "contract_urgent"
        case priceAlert = "price_alert"
        case disputeEscalation = "dispute_escalation"
        case unknown
    }

    init(dictionary: [AnyHashable: Any]) {
        self.alertId = dictionary["alertId"] as? String ?? UUID().uuidString
        self.alertType = AlertType(rawValue: dictionary["type"] as? String ?? "") ?? .unknown
        self.message = dictionary["message"] as? String ?? ""
        self.data = dictionary["data"] as? [String: Any] ?? [:]
        self.timestamp = Date()
    }
}

// MARK: - MTRX Push API

final class MTRXPushAPI {
    static let shared = MTRXPushAPI()

    func registerVoIPToken(_ token: Data) async throws {
        // Register VoIP token with MTRX backend for urgent push delivery
    }

    func invalidateVoIPToken() async throws {
        // Invalidate the current VoIP token on the backend
    }
}
