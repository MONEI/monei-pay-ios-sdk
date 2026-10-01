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

    // MARK: - Universal Link URL Building Tests

    func testBuildUniversalLinkURL_isHttpsPayMoneiAcceptPayment() {
        let url = MoneiPay.buildUniversalLinkURL(
            token: "eyJhbGciOiJIUzI1NiJ9.test",
            amount: 1500,
            completeScheme: "merchant-demo"
        )

        XCTAssertNotNil(url)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.scheme, "https")
        XCTAssertEqual(components?.host, "pay.monei.com")
        XCTAssertEqual(components?.path, "/accept-payment")

        let params = queryParams(from: url!)
        XCTAssertEqual(params["amount"], "1500")
        XCTAssertEqual(params["auth_token"], "eyJhbGciOiJIUzI1NiJ9.test")
        XCTAssertEqual(params["complete_url"], "merchant-demo://payment-result")
    }

    // The Universal Link and custom-scheme URLs must carry identical query params —
    // only scheme/host/path differ. Guards against the two builders drifting.
    func testUniversalLinkAndSchemeURLs_shareIdenticalQueryParams() {
        let args: (String, Int, String) = ("tok", 2500, "my-app")
        let universal = MoneiPay.buildUniversalLinkURL(
            token: args.0,
            amount: args.1,
            description: "Order #42",
            customerName: "Jane Doe",
            callbackUrl: "https://merchant.example.com/webhook",
            orderId: "qmrid:abc-123",
            transactionType: "AUTH",
            completeScheme: args.2
        )
        let scheme = MoneiPay.buildPaymentURL(
            token: args.0,
            amount: args.1,
            description: "Order #42",
            customerName: "Jane Doe",
            callbackUrl: "https://merchant.example.com/webhook",
            orderId: "qmrid:abc-123",
            transactionType: "AUTH",
            completeScheme: args.2
        )
        XCTAssertNotNil(universal)
        XCTAssertNotNil(scheme)
        XCTAssertEqual(queryParams(from: universal!), queryParams(from: scheme!))
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

        // Older MONEI Pay versions send a decline without transaction_id: no result to parse.
        XCTAssertNil(result)
    }

    func testPaymentResult_parsesPaymentFields() {
        let url = URL(string: "app://payment-result?success=true&transaction_id=tx_1&order_id=ord_1&currency=EUR&status=SUCCEEDED&status_code=E000&status_message=Transaction%20approved&authorization_code=A1B2C3&last4=4242&card_type=debit&card_country=ES&masked_card_number=****9999")!
        let result = PaymentResult(from: url)

        XCTAssertEqual(result?.orderId, "ord_1")
        XCTAssertEqual(result?.currency, "EUR")
        XCTAssertEqual(result?.status, "SUCCEEDED")
        XCTAssertEqual(result?.statusCode, "E000")
        XCTAssertEqual(result?.statusMessage, "Transaction approved")
        XCTAssertEqual(result?.authorizationCode, "A1B2C3")
        // An explicit last4 wins over the masked number.
        XCTAssertEqual(result?.last4, "4242")
        XCTAssertEqual(result?.cardType, "debit")
        XCTAssertEqual(result?.cardCountry, "ES")
    }

    // Older MONEI Pay versions send only masked_card_number and no new fields.
    func testPaymentResult_missingNewFieldsAreNil_last4FromMaskedNumber() {
        let url = URL(string: "app://payment-result?success=true&transaction_id=tx_1&masked_card_number=****1234&status_code=")!
        let result = PaymentResult(from: url)

        XCTAssertEqual(result?.last4, "1234")
        XCTAssertNil(result?.orderId)
        XCTAssertNil(result?.currency)
        XCTAssertNil(result?.status)
        XCTAssertNil(result?.statusCode)
        XCTAssertNil(result?.statusMessage)
        XCTAssertNil(result?.authorizationCode)
        XCTAssertNil(result?.cardType)
        XCTAssertNil(result?.cardCountry)
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

    // A decline still throws paymentFailed, and the decline data is exposed for the result screen.
    func testHandleCompleteRedirect_declineExposesDeclinedPayment() async throws {
        let error = try await runPayment(redirect: "app://payment-result?success=false&error=PAYMENT_FAILED&transaction_id=tx_9&order_id=ord_9&status=FAILED&status_code=E301&status_message=Insufficient%20funds")

        guard case .paymentFailed = error as? MoneiPayError else {
            return XCTFail("Expected paymentFailed, got \(String(describing: error))")
        }
        let declined = try XCTUnwrap(MoneiPay.lastDeclinedPayment)
        XCTAssertFalse(declined.success)
        XCTAssertEqual(declined.transactionId, "tx_9")
        XCTAssertEqual(declined.orderId, "ord_9")
        XCTAssertEqual(declined.status, "FAILED")
        XCTAssertEqual(declined.statusCode, "E301")
        XCTAssertEqual(declined.statusMessage, "Insufficient funds")
    }

    // A cancel is not a decline: it must not leave decline data from this or an earlier payment.
    func testHandleCompleteRedirect_cancelLeavesNoDeclinedPayment() async throws {
        _ = try await runPayment(redirect: "app://payment-result?success=false&error=PAYMENT_FAILED&transaction_id=tx_old")
        let error = try await runPayment(redirect: "app://payment-result?success=false&error=CANCELLED&transaction_id=tx_1")

        guard case .paymentCancelled = error as? MoneiPayError else {
            return XCTFail("Expected paymentCancelled, got \(String(describing: error))")
        }
        XCTAssertNil(MoneiPay.lastDeclinedPayment)
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

    /// Start a payment, deliver `redirect` as the complete-redirect URL, return the thrown error.
    private func runPayment(redirect: String) async throws -> Error? {
        let task = Task { try await MoneiPay.acceptPayment(token: "tok", amount: 100, completeScheme: "app") }
        let url = try XCTUnwrap(URL(string: redirect))
        var attempts = 0
        while !MoneiPay.handleCompleteRedirect(url: url) {
            attempts += 1
            if attempts > 1000 {
                task.cancel()
                XCTFail("Payment never became pending")
                return nil
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        do {
            _ = try await task.value
            return nil
        } catch {
            return error
        }
    }

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
