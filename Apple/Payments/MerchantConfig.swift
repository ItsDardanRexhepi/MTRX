import PassKit

/// Apple Pay merchant configuration for MTRX
enum MerchantConfig {
    static let merchantIdentifier = "merchant.com.opnmatrx.mtrx"
    static let countryCode = "US"
    static let defaultCurrency = "USD"

    static let supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex, .discover]
    static let merchantCapabilities: PKMerchantCapability = [.threeDSecure, .debit, .credit]

    static func paymentRequest(amount: NSDecimalNumber, currency: String = defaultCurrency, label: String) -> PKPaymentRequest {
        let request = PKPaymentRequest()
        request.merchantIdentifier = merchantIdentifier
        request.supportedNetworks = supportedNetworks
        request.merchantCapabilities = merchantCapabilities
        request.countryCode = countryCode
        request.currencyCode = currency
        request.paymentSummaryItems = [PKPaymentSummaryItem(label: label, amount: amount)]
        return request
    }
}
