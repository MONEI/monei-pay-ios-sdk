import Foundation

/// Result of a payment processed by MONEI Pay.
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

    public init(
        transactionId: String,
        success: Bool,
        amount: Int? = nil,
        cardBrand: String? = nil,
        maskedCardNumber: String? = nil
    ) {
        self.transactionId = transactionId
        self.success = success
        self.amount = amount
        self.cardBrand = cardBrand
        self.maskedCardNumber = maskedCardNumber
    }

    /// Parse from callback URL query parameters.
    /// Expected params: success, transaction_id, amount, card_brand, masked_card_number, error
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

        guard params["success"] == "true",
              let txId = params["transaction_id"], !txId.isEmpty else {
            return nil
        }

        self.transactionId = txId
        self.success = true
        self.amount = params["amount"].flatMap(Int.init)
        self.cardBrand = params["card_brand"]
        self.maskedCardNumber = params["masked_card_number"]
    }
}
