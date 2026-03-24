import XCTest
@testable import MoneiPaySDK

final class MoneiPayTests: XCTestCase {

    // MARK: - URL Building Tests

    func testBuildPaymentURL_basicParams() {
        let url = MoneiPay.buildPaymentURL(
            token: "eyJhbGciOiJIUzI1NiJ9.test",
            amount: 1500,
            callbackScheme: "merchant-demo"
        )

        XCTAssertNotNil(url)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        XCTAssertEqual(components?.scheme, "monei-pay")
        XCTAssertEqual(components?.host, "accept-payment")

        let params = queryParams(from: url!)
        XCTAssertEqual(params["amount"], "1500")
        XCTAssertEqual(params["auth_token"], "eyJhbGciOiJIUzI1NiJ9.test")
        XCTAssertEqual(params["callback"], "merchant-demo://payment-result")
    }

    func testBuildPaymentURL_allParams() {
        let url = MoneiPay.buildPaymentURL(
            token: "test-token",
            amount: 2500,
            description: "Order #42",
            customerName: "Jane Doe",
            customerEmail: "jane@example.com",
            customerPhone: "+34600000000",
            callbackScheme: "my-app"
        )

        XCTAssertNotNil(url)
        let params = queryParams(from: url!)
        XCTAssertEqual(params["amount"], "2500")
        XCTAssertEqual(params["description"], "Order #42")
        XCTAssertEqual(params["customer_name"], "Jane Doe")
        XCTAssertEqual(params["customer_email"], "jane@example.com")
        XCTAssertEqual(params["customer_phone"], "+34600000000")
        XCTAssertEqual(params["callback"], "my-app://payment-result")
    }

    func testBuildPaymentURL_omitsEmptyOptionals() {
        let url = MoneiPay.buildPaymentURL(
            token: "tok",
            amount: 100,
            description: "",
            customerName: nil,
            callbackScheme: "app"
        )

        XCTAssertNotNil(url)
        let params = queryParams(from: url!)
        XCTAssertNil(params["description"])
        XCTAssertNil(params["customer_name"])
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

        // PaymentResult init returns nil for failed payments (handled separately by handleCallback)
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

    // MARK: - handleCallback Tests

    func testHandleCallback_returnsFlaseWhenNoPending() {
        // No pending payment — should return false
        let url = URL(string: "merchant-demo://payment-result?success=true&transaction_id=tx_1")!
        let handled = MoneiPay.handleCallback(url: url)
        XCTAssertFalse(handled)
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

        XCTAssertTrue(MoneiPayError.paymentFailed(reason: "declined").errorDescription!.contains("declined"))
    }

    // MARK: - Parameter Validation Tests

    func testAcceptPayment_invalidAmount() async {
        do {
            _ = try await MoneiPay.acceptPayment(
                token: "test",
                amount: 0,
                callbackScheme: "app"
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
                callbackScheme: "app"
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
                callbackScheme: "app"
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

    func testAcceptPayment_emptyCallbackScheme() async {
        do {
            _ = try await MoneiPay.acceptPayment(
                token: "test-token",
                amount: 1500,
                callbackScheme: ""
            )
            XCTFail("Expected error for empty callbackScheme")
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
