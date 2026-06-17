import PassKit

/// Apple Pay merchant configuration for MTRX.
///
/// All values come from `PendingCredentials.Payments` (the single config
/// keystone). While the merchant id / processor endpoint are empty, Apple Pay
/// is `isConfigured == false` and the UI keeps the Apple Pay button hidden —
/// the app never presents a chargeable sheet it can't actually settle.
enum MerchantConfig {

    static var merchantIdentifier: String {
        PendingCredentials.filled(PendingCredentials.Payments.applePayMerchantID) ?? ""
    }

    /// Your server-side endpoint that charges the encrypted Apple Pay token via
    /// a real payment processor. `nil` until configured.
    static var processorChargeURL: URL? {
        PendingCredentials.filled(PendingCredentials.Payments.applePayProcessorChargeURL)
            .flatMap(URL.init(string:))
    }

    static var countryCode: String { PendingCredentials.Payments.countryCode }
    static var defaultCurrency: String { PendingCredentials.Payments.currencyCode }

    /// True only when a real charge can be taken end-to-end.
    static var isConfigured: Bool { PendingCredentials.isApplePayConfigured }

    static let supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]
    static let merchantCapabilities: PKMerchantCapability = [.threeDSecure, .debit, .credit]

    static func paymentRequest(amount: NSDecimalNumber, currency: String? = nil, label: String) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantIdentifier
        request.supportedNetworks = supportedNetworks
        request.merchantCapabilities = merchantCapabilities
        request.countryCode = countryCode
        request.currencyCode = currency ?? defaultCurrency
        request.paymentSummaryItems = [PKPaymentSummaryItem(label: label, amount: amount)]
        return request
    }
}
