import Foundation

/// Result of a payment processed by MONEI Pay.
///
/// Display data only. It comes from an untrusted redirect. Before fulfillment, confirm the
/// payment on your server with the signed webhook or `GET /payments/{id}`.
public struct PaymentResult: Sendable {
    /// Unique transaction identifier.
    public let transactionId: String

    /// Whether the payment was approved.
    public let success: Bool

    /// Payment amount in cents.
    public let amount: Int?

    /// Card brand (e.g. "visa", "mastercard").
    public let cardBrand: String?

    /// Masked card number (e.g. "****1234").
    public let maskedCardNumber: String?

    /// Merchant order reference.
    public let orderId: String?

    /// ISO 4217 currency code (e.g. "EUR").
    public let currency: String?

    /// MONEI API payment status (e.g. "SUCCEEDED", "AUTHORIZED", "FAILED").
    public let status: String?

    /// MONEI status code (e.g. "E000", "E301").
    public let statusCode: String?

    /// Human-readable status message (e.g. "Insufficient funds").
    public let statusMessage: String?

    /// Issuer authorization code. Approved payments only.
    public let authorizationCode: String?

    /// Last 4 digits of the card number.
    public let last4: String?

    /// Card type ("credit", "debit" or "prepaid").
    public let cardType: String?

    /// ISO 3166-1 alpha-2 card country code (e.g. "ES").
    public let cardCountry: String?

    public init(
        transactionId: String,
        success: Bool,
        amount: Int? = nil,
        cardBrand: String? = nil,
        maskedCardNumber: String? = nil,
        orderId: String? = nil,
        currency: String? = nil,
        status: String? = nil,
        statusCode: String? = nil,
        statusMessage: String? = nil,
        authorizationCode: String? = nil,
        last4: String? = nil,
        cardType: String? = nil,
        cardCountry: String? = nil
    ) {
        self.transactionId = transactionId
        self.success = success
        self.amount = amount
        self.cardBrand = cardBrand
        self.maskedCardNumber = maskedCardNumber
        self.orderId = orderId
        self.currency = currency
        self.status = status
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.authorizationCode = authorizationCode
        self.last4 = last4
        self.cardType = cardType
        self.cardCountry = cardCountry
    }

    /// Parse from callback URL query parameters.
    /// Expected params: success, transaction_id, amount, card_brand, masked_card_number, order_id,
    /// currency, status, status_code, status_message, authorization_code, last4, card_type,
    /// card_country, error.
    /// Returns nil when `success` is not "true" or "false", or `transaction_id` is missing.
    init?(from url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        let params = queryItems.reduce(into: [String: String]()) { result, item in
            if let value = item.value {
                result[item.name] = value
            }
        }

        guard params["success"] == "true" || params["success"] == "false",
              let txId = params["transaction_id"], !txId.isEmpty else {
            return nil
        }

        func nonEmpty(_ key: String) -> String? {
            guard let value = params[key], !value.isEmpty else { return nil }
            return value
        }

        self.transactionId = txId
        self.success = params["success"] == "true"
        self.amount = params["amount"].flatMap(Int.init)
        self.cardBrand = params["card_brand"]
        self.maskedCardNumber = params["masked_card_number"]
        self.orderId = nonEmpty("order_id")
        self.currency = nonEmpty("currency")
        self.status = nonEmpty("status")
        self.statusCode = nonEmpty("status_code")
        self.statusMessage = nonEmpty("status_message")
        self.authorizationCode = nonEmpty("authorization_code")
        // MONEI Pay versions before last4 support send only masked_card_number.
        self.last4 = nonEmpty("last4") ?? params["masked_card_number"].flatMap(Self.lastFourDigits)
        self.cardType = nonEmpty("card_type")
        self.cardCountry = nonEmpty("card_country")
    }

    /// Last 4 digits of a masked card number (e.g. "****1234" gives "1234").
    private static func lastFourDigits(_ masked: String) -> String? {
        let suffix = masked.suffix(4)
        guard suffix.count == 4, suffix.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return String(suffix)
    }
}
