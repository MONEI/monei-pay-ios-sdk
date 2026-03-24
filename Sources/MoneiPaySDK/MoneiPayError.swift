import Foundation

/// Errors thrown by the MONEI Pay SDK.
public enum MoneiPayError: LocalizedError, Sendable {
    /// MONEI Pay is not installed on this device.
    case moneiPayNotInstalled

    /// A payment is already in progress.
    case paymentInProgress

    /// The payment timed out waiting for MONEI Pay callback.
    case paymentTimeout

    /// The user cancelled the payment.
    case paymentCancelled

    /// The payment was declined or failed.
    case paymentFailed(reason: String?)

    /// Invalid parameters (e.g. amount <= 0).
    case invalidParameters(String)

    /// Failed to open MONEI Pay URL.
    case failedToOpen

    public var errorDescription: String? {
        switch self {
        case .moneiPayNotInstalled:
            return "MONEI Pay is not installed. Install it from the App Store to accept NFC payments."
        case .paymentInProgress:
            return "A payment is already in progress. Wait for it to complete before starting a new one."
        case .paymentTimeout:
            return "Payment timed out. MONEI Pay did not return a result in time."
        case .paymentCancelled:
            return "Payment was cancelled."
        case .paymentFailed(let reason):
            if let reason {
                return "Payment failed: \(reason)"
            }
            return "Payment failed."
        case .invalidParameters(let message):
            return "Invalid parameters: \(message)"
        case .failedToOpen:
            return "Failed to open MONEI Pay."
        }
    }
}
