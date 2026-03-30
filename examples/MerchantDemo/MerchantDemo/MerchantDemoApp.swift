import SwiftUI
import MoneiPaySDK

// MARK: - Merchant Demo App
// Minimal demo showing how to integrate with MONEI Pay SDK for NFC payments.
// No special entitlements, certificates, or Apple approvals are needed.

@main
struct MerchantDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Wire SDK callback handler — this resumes the pending acceptPayment() call
                .onOpenURL { url in
                    MoneiPay.handleCallback(url: url)
                }
        }
    }
}
