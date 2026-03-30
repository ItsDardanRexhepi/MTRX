import PassKit

/// Apple Pay integration for Component 17 cross-border payments
@MainActor
final class PassKitManager: NSObject, ObservableObject {
    @Published var canMakePayments = false

    override init() {
        super.init()
        canMakePayments = PKPaymentAuthorizationController.canMakePayments(
            usingNetworks: Self.supportedNetworks,
            capabilities: .threeDSecure
        )
    }

    static let supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]

    func processPayment(amount: NSDecimalNumber, currency: String, label: String) async throws -> PKPayment {
        let request = PKPaymentRequest()
        request.merchantIdentifier = MerchantConfig.merchantIdentifier
        request.supportedNetworks = Self.supportedNetworks
        request.merchantCapabilities = .threeDSecure
        request.countryCode = MerchantConfig.countryCode
        request.currencyCode = currency
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: label, amount: amount)
        ]

        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PaymentDelegate(continuation: continuation)
            controller.delegate = delegate
            controller.present { presented in
                if !presented { continuation.resume(throwing: PassKitError.presentationFailed) }
            }
        }
    }

    enum PassKitError: Error { case presentationFailed, paymentFailed, cancelled }
}

private class PaymentDelegate: NSObject, PKPaymentAuthorizationControllerDelegate {
    let continuation: CheckedContinuation<PKPayment, Error>
    private var completed = false

    init(continuation: CheckedContinuation<PKPayment, Error>) { self.continuation = continuation }

    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                         didAuthorizePayment payment: PKPayment,
                                         handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        completed = true
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
        continuation.resume(returning: payment)
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss { [self] in
            if !completed { continuation.resume(throwing: PassKitManager.PassKitError.cancelled) }
        }
    }
}
