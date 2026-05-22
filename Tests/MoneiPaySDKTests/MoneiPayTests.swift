import XCTest
@testable import MoneiPaySDK

final class MoneiPayTests: XCTestCase {

    // MARK: - URL Building Tests

    func testBuildPaymentURL_basicParams() {
        let url = MoneiPay.buildPaymentURL(
            token: "eyJhbGciOiJIUzI1NiJ9.test",
            amount: 1500,
            completeScheme: "merchant-demo"
        )

        XCTAssertNotNil(url)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.scheme, "monei-pay")
        XCTAssertEqual(components?.host, "accept-payment")

        let params = queryParams(from: url!)
        XCTAssertEqual(params["amount"], "1500")
        XCTAssertEqual(params["auth_token"], "eyJhbGciOiJIUzI1NiJ9.test")
        XCTAssertEqual(params["complete_url"], "merchant-demo://payment-result")
        // Regression: legacy `callback` query item must never appear.
        XCTAssertNil(params["callback"])
        XCTAssertNil(params["callback_url"])
    }

    func testBuildPaymentURL_allParams() {
        let url = MoneiPay.buildPaymentURL(
            token: "test-token",
            amount: 2500,
            description: "Order #42",
            customerName: "Jane Doe",
            customerEmail: "jane@example.com",
            customerPhone: "+34600000000",
            callbackUrl: "https://merchant.example.com/webhook",
            completeScheme: "my-app"
        )

        XCTAssertNotNil(url)
        let params = queryParams(from: url!)
        XCTAssertEqual(params["amount"], "2500")
        XCTAssertEqual(params["description"], "Order #42")
        XCTAssertEqual(params["customer_name"], "Jane Doe")
        XCTAssertEqual(params["customer_email"], "jane@example.com")
        XCTAssertEqual(params["customer_phone"], "+34600000000")
        XCTAssertEqual(params["complete_url"], "my-app://payment-result")
        XCTAssertEqual(params["callback_url"], "https://merchant.example.com/webhook")
        XCTAssertNil(params["callback"])
    }

    func testBuildPaymentURL_omitsEmptyOptionals() {
        let url = MoneiPay.buildPaymentURL(
            token: "tok",
            amount: 100,
            description: "",
            customerName: nil,
            completeScheme: "app"
        )

        XCTAssertNotNil(url)
        let params = queryParams(from: url!)
        XCTAssertNil(params["description"])
        XCTAssertNil(params["customer_name"])
        XCTAssertNil(params["callback_url"])
    }

    // Merchant orderId surfaces as order_id query param for backend reconciliation.
    // transactionType passes through unvalidated; backend zod enforces enum.
    func testBuildPaymentURL_emitsOrderIdAndTransactionType() {
        let url = MoneiPay.buildPaymentURL(
            token: "tok",
            amount: 100,
            callbackUrl: nil,
            orderId: "qmrid:abc-123",
            transactionType: "AUTH",
            completeScheme: "app"
        )
        XCTAssertNotNil(url)
        let params = queryParams(from: url!)
        XCTAssertEqual(params["order_id"], "qmrid:abc-123")
        XCTAssertEqual(params["transaction_type"], "AUTH")
    }

    func testBuildPaymentURL_omitsOrderIdAndTransactionTypeWhenNilOrEmpty() {
        let url = MoneiPay.buildPaymentURL(
            token: "tok",
            amount: 100,
            orderId: "",
            transactionType: nil,
            completeScheme: "app"
        )
        XCTAssertNotNil(url)
        let params = queryParams(from: url!)
        XCTAssertNil(params["order_id"])
        XCTAssertNil(params["transaction_type"])
    }

    func testBuildPaymentURL_emitsCompleteUrlNotLegacyCallback() {
        // Negative regression: even with minimal params, NO `callback` key appears.
        let url = MoneiPay.buildPaymentURL(
            token: "t",
            amount: 1,
            completeScheme: "x"
        )
        XCTAssertNotNil(url)
        let params = queryParams(from: url!)
        XCTAssertNil(params["callback"], "Legacy `callback` query item must not appear in built URL")
        XCTAssertEqual(params["complete_url"], "x://payment-result")
    }

    // MARK: - isValidCallbackUrl Tests

    func testIsValidCallbackUrl_https_passes() {
        XCTAssertTrue(MoneiPay.isValidCallbackUrl("https://merchant.example.com/hook"))
    }

    func testIsValidCallbackUrl_http_rejected() {
        XCTAssertFalse(MoneiPay.isValidCallbackUrl("http://merchant.example.com/hook"))
    }

    func testIsValidCallbackUrl_customScheme_rejected() {
        XCTAssertFalse(MoneiPay.isValidCallbackUrl("myapp://payment-result"))
    }

    func testIsValidCallbackUrl_tooLong_rejected() {
        let long = "https://example.com/" + String(repeating: "a", count: 2100)
        XCTAssertFalse(MoneiPay.isValidCallbackUrl(long))
    }

    func testIsValidCallbackUrl_empty_rejected() {
        XCTAssertFalse(MoneiPay.isValidCallbackUrl(""))
    }

    // MARK: - PaymentResult Parsing Tests

    func testPaymentResult_successParsing() {
        let url = URL(string: "merchant-demo://payment-result?success=true&transaction_id=tx_123&amount=1500&card_brand=visa&masked_card_number=****1234")!
        let result = PaymentResult(from: url)

        XCTAssertNotNil(result)
        XCTAssertTrue(result!.success)
        XCTAssertEqual(result!.transactionId, "tx_123")
        XCTAssertEqual(result!.amount, 1500)
        XCTAssertEqual(result!.cardBrand, "visa")
        XCTAssertEqual(result!.maskedCardNumber, "****1234")
    }

    func testPaymentResult_failedParsing() {
        let url = URL(string: "merchant-demo://payment-result?success=false&error=PAYMENT_FAILED")!
        let result = PaymentResult(from: url)

        // PaymentResult init returns nil for failed payments (handled separately by handleCompleteRedirect)
        XCTAssertNil(result)
    }

    func testPaymentResult_missingTransactionId() {
        let url = URL(string: "merchant-demo://payment-result?success=true")!
        let result = PaymentResult(from: url)

        // Missing transaction_id should fail parsing
        XCTAssertNil(result)
    }

    func testPaymentResult_noQueryParams() {
        let url = URL(string: "merchant-demo://payment-result")!
        let result = PaymentResult(from: url)
        XCTAssertNil(result)
    }

    // MARK: - handleCompleteRedirect Tests

    func testHandleCompleteRedirect_returnsFalseWhenNoPending() {
        // No pending payment — should return false
        let url = URL(string: "merchant-demo://payment-result?success=true&transaction_id=tx_1")!
        let handled = MoneiPay.handleCompleteRedirect(url: url)
        XCTAssertFalse(handled)
    }

    // MARK: - Error Code Mapping

    func testMapErrorCode_cancelled() {
        if case .paymentCancelled = MoneiPay.mapErrorCode("CANCELLED") {} else {
            XCTFail("CANCELLED should map to .paymentCancelled")
        }
        if case .paymentCancelled = MoneiPay.mapErrorCode("USER_CANCELLED") {} else {
            XCTFail("USER_CANCELLED should map to .paymentCancelled")
        }
    }

    func testMapErrorCode_tokenExpired() {
        if case .tokenExpired = MoneiPay.mapErrorCode("TOKEN_EXPIRED") {} else {
            XCTFail("TOKEN_EXPIRED should map to .tokenExpired")
        }
    }

    func testMapErrorCode_invalidToken() {
        if case .invalidToken = MoneiPay.mapErrorCode("INVALID_TOKEN") {} else {
            XCTFail("INVALID_TOKEN should map to .invalidToken")
        }
    }

    func testMapErrorCode_invalidAmount() {
        if case .invalidParameters(let msg) = MoneiPay.mapErrorCode("INVALID_AMOUNT") {
            XCTAssertTrue(msg.lowercased().contains("amount"))
        } else {
            XCTFail("INVALID_AMOUNT should map to .invalidParameters")
        }
    }

    func testMapErrorCode_invalidCallbackUrl() {
        if case .invalidParameters(let msg) = MoneiPay.mapErrorCode("INVALID_CALLBACK_URL") {
            XCTAssertTrue(msg.lowercased().contains("callback"))
        } else {
            XCTFail("INVALID_CALLBACK_URL should map to .invalidParameters")
        }
    }

    func testMapErrorCode_invalidCompleteUrl() {
        if case .invalidParameters(let msg) = MoneiPay.mapErrorCode("INVALID_COMPLETE_URL") {
            XCTAssertTrue(msg.lowercased().contains("complete"))
        } else {
            XCTFail("INVALID_COMPLETE_URL should map to .invalidParameters")
        }
    }

    func testMapErrorCode_invalidCallbackLegacy() {
        if case .invalidParameters = MoneiPay.mapErrorCode("INVALID_CALLBACK") {} else {
            XCTFail("INVALID_CALLBACK should map to .invalidParameters")
        }
    }

    func testMapErrorCode_notAuthenticated() {
        if case .notAuthenticated = MoneiPay.mapErrorCode("NOT_AUTHENTICATED") {} else {
            XCTFail("NOT_AUTHENTICATED should map to .notAuthenticated")
        }
    }

    func testMapErrorCode_accountNotConfigured() {
        if case .accountNotConfigured = MoneiPay.mapErrorCode("ACCOUNT_NOT_CONFIGURED") {} else {
            XCTFail("ACCOUNT_NOT_CONFIGURED should map to .accountNotConfigured")
        }
    }

    func testMapErrorCode_paymentFailed() {
        if case .paymentFailed(let reason) = MoneiPay.mapErrorCode("PAYMENT_FAILED") {
            XCTAssertNil(reason)
        } else {
            XCTFail("PAYMENT_FAILED should map to .paymentFailed(nil)")
        }
    }

    func testMapErrorCode_unknownPassesThrough() {
        if case .paymentFailed(let reason) = MoneiPay.mapErrorCode("SOMETHING_NEW") {
            XCTAssertEqual(reason, "SOMETHING_NEW")
        } else {
            XCTFail("Unknown code should pass through as paymentFailed reason")
        }
    }

    func testMapErrorCode_nilPassesThrough() {
        if case .paymentFailed(let reason) = MoneiPay.mapErrorCode(nil) {
            XCTAssertNil(reason)
        } else {
            XCTFail("nil code should map to paymentFailed(nil)")
        }
    }

    // MARK: - Error Tests

    func testMoneiPayError_descriptions() {
        XCTAssertNotNil(MoneiPayError.moneiPayNotInstalled.errorDescription)
        XCTAssertNotNil(MoneiPayError.paymentInProgress.errorDescription)
        XCTAssertNotNil(MoneiPayError.paymentTimeout.errorDescription)
        XCTAssertNotNil(MoneiPayError.paymentCancelled.errorDescription)
        XCTAssertNotNil(MoneiPayError.paymentFailed(reason: nil).errorDescription)
        XCTAssertNotNil(MoneiPayError.paymentFailed(reason: "declined").errorDescription)
        XCTAssertNotNil(MoneiPayError.invalidParameters("test").errorDescription)
        XCTAssertNotNil(MoneiPayError.failedToOpen.errorDescription)
        XCTAssertNotNil(MoneiPayError.tokenExpired.errorDescription)
        XCTAssertNotNil(MoneiPayError.invalidToken.errorDescription)
        XCTAssertNotNil(MoneiPayError.notAuthenticated.errorDescription)
        XCTAssertNotNil(MoneiPayError.accountNotConfigured.errorDescription)

        XCTAssertTrue(MoneiPayError.paymentFailed(reason: "declined").errorDescription!.contains("declined"))
    }

    // MARK: - Parameter Validation Tests

    func testAcceptPayment_invalidAmount() async {
        do {
            _ = try await MoneiPay.acceptPayment(
                token: "test",
                amount: 0,
                completeScheme: "app"
            )
            XCTFail("Expected error for zero amount")
        } catch let error as MoneiPayError {
            if case .invalidParameters = error {
                // Expected
            } else {
                XCTFail("Expected invalidParameters, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAcceptPayment_negativeAmount() async {
        do {
            _ = try await MoneiPay.acceptPayment(
                token: "test",
                amount: -100,
                completeScheme: "app"
            )
            XCTFail("Expected error for negative amount")
        } catch let error as MoneiPayError {
            if case .invalidParameters = error {
                // Expected
            } else {
                XCTFail("Expected invalidParameters, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAcceptPayment_emptyToken() async {
        do {
            _ = try await MoneiPay.acceptPayment(
                token: "",
                amount: 1500,
                completeScheme: "app"
            )
            XCTFail("Expected error for empty token")
        } catch let error as MoneiPayError {
            if case .invalidParameters = error {
                // Expected
            } else {
                XCTFail("Expected invalidParameters, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAcceptPayment_emptyCompleteScheme() async {
        do {
            _ = try await MoneiPay.acceptPayment(
                token: "test-token",
                amount: 1500,
                completeScheme: ""
            )
            XCTFail("Expected error for empty completeScheme")
        } catch let error as MoneiPayError {
            if case .invalidParameters = error {
                // Expected
            } else {
                XCTFail("Expected invalidParameters, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testAcceptPayment_invalidCallbackUrl_httpRejected() async {
        do {
            _ = try await MoneiPay.acceptPayment(
                token: "test-token",
                amount: 1500,
                callbackUrl: "http://insecure.example.com/hook",
                completeScheme: "app"
            )
            XCTFail("Expected error for http callbackUrl")
        } catch let error as MoneiPayError {
            if case .invalidParameters = error {
                // Expected
            } else {
                XCTFail("Expected invalidParameters, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Helpers

    private func queryParams(from url: URL) -> [String: String] {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .reduce(into: [String: String]()) { result, item in
                if let value = item.value {
                    result[item.name] = value
                }
            } ?? [:]
    }
}
