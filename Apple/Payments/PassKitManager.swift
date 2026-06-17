import PassKit
import Foundation

/// Apple Pay integration.
///
/// Presents the real Apple Pay sheet and settles the charge through a
/// server-side payment processor. It reports success ONLY when the processor
/// confirms a real charge — it never optimistically reports "paid". When the
/// merchant id / processor endpoint aren't configured (see
/// `PendingCredentials.Payments`), `isAvailable` is false and no sheet is
/// presented, so the app can't show a charge it didn't make.
@MainActor
final class PassKitManager: NSObject, ObservableObject {

    @Published private(set) var isAvailable = false

    private var controller: PKPaymentAuthorizationController?
    private var delegate: PaymentDelegate?

    override init() {
        super.init()
        refreshAvailability()
    }

    /// Apple Pay is offered only when the device can pay AND a merchant id +
    /// processor endpoint are configured.
    func refreshAvailability() {
        isAvailable = MerchantConfig.isConfigured &&
            PKPaymentAuthorizationController.canMakePayments(
                usingNetworks: MerchantConfig.supportedNetworks,
                capabilities: .threeDSecure
            )
    }

    enum PassKitError: LocalizedError {
        case notConfigured
        case presentationFailed
        case cancelled
        case chargeFailed(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:      return "Apple Pay isn't set up yet."
            case .presentationFailed: return "Couldn't present Apple Pay."
            case .cancelled:          return "Payment cancelled."
            case .chargeFailed(let r): return "Payment failed: \(r)"
            }
        }
    }

    /// Present Apple Pay and settle the charge. Returns only on a CONFIRMED
    /// charge; throws on cancellation or a processor failure.
    func charge(amount: NSDecimalNumber, currency: String? = nil, label: String) async throws {
        guard MerchantConfig.isConfigured, let chargeURL = MerchantConfig.processorChargeURL else {
            throw PassKitError.notConfigured
        }

        let request = MerchantConfig.paymentRequest(amount: amount, currency: currency, label: label)
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        self.controller = controller
        defer { self.controller = nil; self.delegate = nil }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = PaymentDelegate(chargeURL: chargeURL, continuation: continuation)
            self.delegate = delegate           // PKPaymentAuthorizationController.delegate is weak
            controller.delegate = delegate
            controller.present { presented in
                if !presented {
                    continuation.resume(throwing: PassKitError.presentationFailed)
                }
            }
        }
    }
}

// MARK: - Delegate

private final class PaymentDelegate: NSObject, PKPaymentAuthorizationControllerDelegate {
    private let chargeURL: URL
    private let continuation: CheckedContinuation<Void, Error>
    private var settled = false

    init(chargeURL: URL, continuation: CheckedContinuation<Void, Error>) {
        self.chargeURL = chargeURL
        self.continuation = continuation
    }

    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                         didAuthorizePayment payment: PKPayment,
                                         handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        // Submit the ENCRYPTED token to the processor; only report success when
        // the server confirms a real charge.
        Task {
            do {
                try await self.submitCharge(payment)
                self.settled = true
                completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                self.continuation.resume()
            } catch {
                self.settled = true
                completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                self.continuation.resume(throwing: PassKitManager.PassKitError.chargeFailed(error.localizedDescription))
            }
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [self] in
            if !settled {
                settled = true
                continuation.resume(throwing: PassKitManager.PassKitError.cancelled)
            }
        }
    }

    /// POST the encrypted Apple Pay token to the processor endpoint. Non-2xx
    /// means the charge did not go through.
    private func submitCharge(_ payment: PKPayment) async throws {
        var req = URLRequest(url: chargeURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "paymentData": payment.token.paymentData.base64EncodedString(),
            "transactionIdentifier": payment.token.transactionIdentifier,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PassKitManager.PassKitError.chargeFailed("processor returned \(code)")
        }
    }
}
