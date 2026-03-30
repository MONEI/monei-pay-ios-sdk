# MONEI Pay iOS SDK

Accept NFC tap-to-pay payments in your iOS app via [MONEI Pay](https://monei.com/monei-pay/).

No special entitlements, certificates, or Apple approval needed — your app opens MONEI Pay, which handles the NFC payment, then calls back with the result.

## Requirements

- iOS 15.0+
- MONEI Pay installed on device
- POS auth token from your backend (`POST /v1/pos/auth-token`)

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/MONEI/monei-pay-ios-sdk.git", from: "0.2.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste `https://github.com/MONEI/monei-pay-ios-sdk.git`

## Setup

### 1. Register your callback URL scheme

In your app's `Info.plist`, register a custom URL scheme (e.g. your bundle ID):

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>my-merchant-app</string>
        </array>
    </dict>
</array>
```

### 2. Add MONEI Pay to queried schemes

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>monei-pay</string>
</array>
```

### 3. Wire the callback handler

**SwiftUI:**

```swift
@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    MoneiPay.handleCallback(url: url)
                }
        }
    }
}
```

**UIKit:**

```swift
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    return MoneiPay.handleCallback(url: url)
}
```

## Usage

```swift
import MoneiPaySDK

do {
    let result = try await MoneiPay.acceptPayment(
        token: "eyJ...",              // Raw JWT from your backend (no "Bearer " prefix)
        amount: 1500,                 // Amount in cents (1500 = 15.00 EUR)
        description: "Order #123",    // Optional
        customerName: "John Doe",     // Optional
        customerEmail: "john@ex.com", // Optional
        customerPhone: "+34600000000",// Optional
        callbackScheme: "my-merchant-app"  // Your registered URL scheme
    )

    print("Payment approved: \(result.transactionId)")
    print("Card: \(result.cardBrand ?? "") \(result.maskedCardNumber ?? "")")
} catch MoneiPayError.moneiPayNotInstalled {
    // Prompt user to install MONEI Pay
} catch MoneiPayError.paymentCancelled {
    // User cancelled
} catch MoneiPayError.paymentTimeout {
    // MONEI Pay didn't respond in time
} catch {
    print("Payment failed: \(error.localizedDescription)")
}
```

## API Reference

### `MoneiPay.acceptPayment(...)`

Accepts an NFC payment via MONEI Pay.

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `token` | `String` | Yes | Raw JWT auth token (no "Bearer " prefix) |
| `amount` | `Int` | Yes | Amount in cents |
| `description` | `String?` | No | Payment description |
| `customerName` | `String?` | No | Customer name |
| `customerEmail` | `String?` | No | Customer email |
| `customerPhone` | `String?` | No | Customer phone |
| `callbackScheme` | `String` | Yes | Your app's registered URL scheme |
| `timeout` | `TimeInterval?` | No | Timeout in seconds (default: 60) |

Returns `PaymentResult`. Throws `MoneiPayError`.

### `MoneiPay.handleCallback(url:)`

Handle incoming callback URL from MONEI Pay. Returns `true` if the URL was handled.

### `PaymentResult`

| Property | Type | Description |
|----------|------|-------------|
| `transactionId` | `String` | Unique transaction ID |
| `success` | `Bool` | Whether payment was approved |
| `amount` | `Int?` | Amount in cents |
| `cardBrand` | `String?` | Card brand (visa, mastercard, etc.) |
| `maskedCardNumber` | `String?` | Masked card number (****1234) |

### `MoneiPayError`

| Case | Description |
|------|-------------|
| `.moneiPayNotInstalled` | MONEI Pay not on device |
| `.paymentInProgress` | Another payment is active |
| `.paymentTimeout` | Callback not received in time |
| `.paymentCancelled` | User cancelled |
| `.paymentFailed(reason:)` | Payment declined/failed |
| `.invalidParameters(_)` | Invalid input parameters |
| `.failedToOpen` | Could not open MONEI Pay |

## Example App

The [`examples/MerchantDemo`](examples/MerchantDemo) directory contains a minimal SwiftUI app demonstrating the full integration flow: enter an API key, fetch a POS auth token, and accept an NFC payment via MONEI Pay.

To run:

1. Open `examples/MerchantDemo/MerchantDemo.xcodeproj` in Xcode
2. Set your Apple Development Team in **Signing & Capabilities**
3. Build and run on a device with MONEI Pay installed

The demo references the SDK as a local Swift package (`../../`), so any local SDK changes are picked up immediately.

> **Beta:** MONEI Pay for iOS is currently in beta. Join via [TestFlight](https://testflight.apple.com/join/kZU2j445).

## Token Generation

Your backend generates POS auth tokens via the MONEI API:

```bash
curl -X POST https://api.monei.com/v1/pos/auth-token \
  -H "Authorization: YOUR_API_KEY" \
  -H "Content-Type: application/json"
```

See the [MONEI API docs](https://docs.monei.com) for details.

## License

MIT
