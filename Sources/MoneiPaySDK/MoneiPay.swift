import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// MONEI Pay SDK for accepting NFC payments via the MONEI Pay app.
///
/// Two complementary result channels:
///
/// - `completeScheme`: your app's URL scheme. MONEI Pay opens
///   `<completeScheme>://payment-result?...` when the flow finishes (success,
///   cancel, or error). This is the **UX redirect** — fast, client-side, NOT
///   cryptographically trusted. Use it to drive UI, never order fulfillment.
/// - `callbackUrl` (optional): an HTTPS endpoint on your backend. MONEI fires
///   a signed webhook (HMAC `MONEI-Signature`) here on payment completion.
///   This is the **trusted** channel — use it for fulfillment, accounting,
///   anything irreversible. Pair both for production.
///
/// Usage:
/// ```swift
/// let result = try await MoneiPay.acceptPayment(
///     token: "eyJ...",
///     amount: 1500,
///     callbackUrl: "https://merchant.example.com/webhook/monei",
///     completeScheme: "my-merchant-app"
/// )
/// ```
///
/// You must also wire `MoneiPay.handleCompleteRedirect(url:)` in your app's URL handler.
public final class MoneiPay: @unchecked Sendable {

    /// Default timeout in seconds for waiting for MONEI Pay callback.
    public static var defaultTimeout: TimeInterval = 60

    /// URL scheme used to open MONEI Pay.
    static let moneiPayScheme = "monei-pay"

    // MARK: - Internal State

    /// Pending continuation waiting for callback URL.
    private static var pendingContinuation: CheckedContinuation<PaymentResult, Error>?

    /// Lock for thread-safe access to pendingContinuation.
    private static let lock = NSLock()

    /// Timestamp when the current payment started (wall clock for timeout).
    private static var paymentStartDate: Date?

    private init() {}

    // MARK: - Public API

    /// Accept an NFC payment via MONEI Pay.
    ///
    /// - Parameters:
    ///   - token: Raw JWT auth token (without "Bearer " prefix).
    ///   - amount: Payment amount in cents (e.g. 1500 = 15.00 EUR).
    ///   - description: Optional payment description.
    ///   - customerName: Optional customer name.
    ///   - customerEmail: Optional customer email.
    ///   - customerPhone: Optional customer phone.
    ///   - callbackUrl: Optional HTTPS endpoint for the signed webhook on payment completion.
    ///     Must be `https://`, max 2048 chars. This is the trusted channel — use it for fulfillment.
    ///   - completeScheme: Your app's registered URL scheme (e.g. "my-merchant-app").
    ///     MONEI Pay opens `<completeScheme>://payment-result` when the flow ends. UX-only, untrusted.
    ///   - timeout: Timeout in seconds (default: 60). Uses wall-clock time, not Task.sleep.
    /// - Returns: A `PaymentResult` with transaction details.
    /// - Throws: `MoneiPayError` on failure.
    public static func acceptPayment(
        token: String,
        amount: Int,
        description: String? = nil,
        customerName: String? = nil,
        customerEmail: String? = nil,
        customerPhone: String? = nil,
        callbackUrl: String? = nil,
        completeScheme: String,
        timeout: TimeInterval? = nil
    ) async throws -> PaymentResult {
        // Validate parameters
        guard amount > 0 else {
            throw MoneiPayError.invalidParameters("amount must be positive")
        }
        guard !token.isEmpty else {
            throw MoneiPayError.invalidParameters("token must not be empty")
        }
        guard !completeScheme.isEmpty else {
            throw MoneiPayError.invalidParameters("completeScheme must not be empty")
        }
        if let callbackUrl {
            guard isValidCallbackUrl(callbackUrl) else {
                throw MoneiPayError.invalidParameters("callbackUrl must be https:// and <= 2048 chars")
            }
        }

        // Guard against concurrent calls
        lock.lock()
        if pendingContinuation != nil {
            lock.unlock()
            throw MoneiPayError.paymentInProgress
        }
        lock.unlock()

        // Check MONEI Pay is installed
        #if canImport(UIKit)
        let isInstalled = await checkMoneiPayInstalled()
        guard isInstalled else {
            throw MoneiPayError.moneiPayNotInstalled
        }
        #endif

        // Build MONEI Pay URL
        guard let url = buildPaymentURL(
            token: token,
            amount: amount,
            description: description,
            customerName: customerName,
            customerEmail: customerEmail,
            customerPhone: customerPhone,
            callbackUrl: callbackUrl,
            completeScheme: completeScheme
        ) else {
            throw MoneiPayError.invalidParameters("Failed to build payment URL")
        }

        let effectiveTimeout = timeout ?? defaultTimeout

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            // Double-check after acquiring lock
            if pendingContinuation != nil {
                lock.unlock()
                continuation.resume(throwing: MoneiPayError.paymentInProgress)
                return
            }
            pendingContinuation = continuation
            paymentStartDate = Date()
            lock.unlock()

            // Open MONEI Pay
            Task { @MainActor in
                #if canImport(UIKit)
                let opened = await UIApplication.shared.open(url)
                if !opened {
                    resumePendingContinuation(with: .failure(MoneiPayError.failedToOpen))
                    return
                }
                #endif

                // Start timeout monitoring
                startTimeoutMonitor(timeout: effectiveTimeout)
            }
        }
    }

    /// Handle a complete-redirect URL from MONEI Pay.
    ///
    /// Wire this into your SwiftUI app:
    /// ```swift
    /// .onOpenURL { url in
    ///     MoneiPay.handleCompleteRedirect(url: url)
    /// }
    /// ```
    ///
    /// Or in UIKit AppDelegate:
    /// ```swift
    /// func application(_ app: UIApplication, open url: URL, options: ...) -> Bool {
    ///     return MoneiPay.handleCompleteRedirect(url: url)
    /// }
    /// ```
    ///
    /// - Parameter url: The incoming URL.
    /// - Returns: `true` if the URL was handled by the SDK.
    @discardableResult
    public static func handleCompleteRedirect(url: URL) -> Bool {
        lock.lock()
        guard pendingContinuation != nil else {
            lock.unlock()
            return false
        }
        lock.unlock()

        // Check for error callback
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = components?.queryItems?.reduce(into: [String: String]()) { result, item in
            if let value = item.value {
                result[item.name] = value
            }
        } ?? [:]

        if params["success"] == "false" {
            let errorReason = params["error"]
            resumePendingContinuation(with: .failure(mapErrorCode(errorReason)))
            return true
        }

        // Parse success result
        if let result = PaymentResult(from: url) {
            resumePendingContinuation(with: .success(result))
            return true
        }

        // URL had query params but couldn't parse a valid result
        resumePendingContinuation(with: .failure(MoneiPayError.paymentFailed(reason: "Invalid callback parameters")))
        return true
    }

    /// Cancel any pending payment. The continuation will resume with `paymentCancelled`.
    public static func cancelPendingPayment() {
        resumePendingContinuation(with: .failure(MoneiPayError.paymentCancelled))
    }

    // MARK: - Internal Helpers

    /// Map a `?error=...` code from the complete redirect URL to a typed `MoneiPayError`.
    /// Codes mirror the set emitted by the monei-pay app's deep-link error path.
    static func mapErrorCode(_ code: String?) -> MoneiPayError {
        switch code {
        case "CANCELLED", "USER_CANCELLED":
            return .paymentCancelled
        case "TOKEN_EXPIRED":
            return .tokenExpired
        case "INVALID_TOKEN":
            return .invalidToken
        case "INVALID_AMOUNT":
            return .invalidParameters("Invalid amount")
        case "INVALID_CALLBACK_URL":
            return .invalidParameters("Invalid callback_url (must be https and not a private IP)")
        case "INVALID_COMPLETE_URL":
            return .invalidParameters("Invalid complete_url (blocked scheme or malformed)")
        case "INVALID_CALLBACK":
            // Legacy code from app versions before v3.0. Should not appear with SDK >= 1.0.
            return .invalidParameters("Invalid callback (legacy)")
        case "NOT_AUTHENTICATED":
            return .notAuthenticated
        case "ACCOUNT_NOT_CONFIGURED":
            return .accountNotConfigured
        case "PAYMENT_FAILED":
            return .paymentFailed(reason: nil)
        default:
            return .paymentFailed(reason: code)
        }
    }

    /// Validate a `callbackUrl` value: must be `https://` and ≤ 2048 chars.
    /// Sanity-check only. The real defense is server-side in mcc-service/payments-service.
    /// Must mirror lib/deep-link-utils.ts isValidCallbackUrl in the monei-pay app — keep in sync.
    static func isValidCallbackUrl(_ url: String) -> Bool {
        guard url.count <= 2048 else { return false }
        guard URL(string: url) != nil else { return false }
        return url.lowercased().hasPrefix("https://")
    }

    /// Build the MONEI Pay deep link URL.
    static func buildPaymentURL(
        token: String,
        amount: Int,
        description: String? = nil,
        customerName: String? = nil,
        customerEmail: String? = nil,
        customerPhone: String? = nil,
        callbackUrl: String? = nil,
        completeScheme: String
    ) -> URL? {
        var components = URLComponents()
        components.scheme = moneiPayScheme
        components.host = "accept-payment"

        var queryItems = [
            URLQueryItem(name: "amount", value: String(amount)),
            URLQueryItem(name: "auth_token", value: token),
            URLQueryItem(name: "complete_url", value: "\(completeScheme)://payment-result")
        ]

        if let callbackUrl, !callbackUrl.isEmpty {
            queryItems.append(URLQueryItem(name: "callback_url", value: callbackUrl))
        }
        if let description, !description.isEmpty {
            queryItems.append(URLQueryItem(name: "description", value: description))
        }
        if let customerName, !customerName.isEmpty {
            queryItems.append(URLQueryItem(name: "customer_name", value: customerName))
        }
        if let customerEmail, !customerEmail.isEmpty {
            queryItems.append(URLQueryItem(name: "customer_email", value: customerEmail))
        }
        if let customerPhone, !customerPhone.isEmpty {
            queryItems.append(URLQueryItem(name: "customer_phone", value: customerPhone))
        }

        components.queryItems = queryItems
        return components.url
    }

    #if canImport(UIKit)
    @MainActor
    private static func checkMoneiPayInstalled() -> Bool {
        guard let url = URL(string: "\(moneiPayScheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    #endif

    /// Monitor timeout using wall-clock time (not Task.sleep, which pauses when backgrounded).
    private static func startTimeoutMonitor(timeout: TimeInterval) {
        #if canImport(UIKit)
        // Listen for app returning to foreground to check elapsed time
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            checkTimeoutExpired()
        }

        // Also schedule a delayed check for cases where the app stays in foreground
        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            checkTimeoutExpired()
            NotificationCenter.default.removeObserver(observer)
        }
        #endif
    }

    private static func checkTimeoutExpired() {
        lock.lock()
        guard pendingContinuation != nil, let startDate = paymentStartDate else {
            lock.unlock()
            return
        }
        let elapsed = Date().timeIntervalSince(startDate)
        let timeout = defaultTimeout
        lock.unlock()

        if elapsed >= timeout {
            resumePendingContinuation(with: .failure(MoneiPayError.paymentTimeout))
        }
    }

    /// Thread-safe resume of the pending continuation.
    private static func resumePendingContinuation(with result: Result<PaymentResult, Error>) {
        lock.lock()
        guard let continuation = pendingContinuation else {
            lock.unlock()
            return
        }
        pendingContinuation = nil
        paymentStartDate = nil
        lock.unlock()

        continuation.resume(with: result)
    }
}
