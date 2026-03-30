# iOS Merchant Demo

Minimal SwiftUI app showing how to integrate with MONEI Pay for NFC payments using the [MoneiPaySDK](https://github.com/MONEI/monei-pay-ios-sdk).

**No entitlements, certificates, or Apple approval needed.**

## Prerequisites

- Xcode 15.0+
- iOS 17.4+ device
- MONEI Pay installed on the same device

## Setup

1. Open `MerchantDemo.xcodeproj` in Xcode
2. Select your Apple Development Team in **Signing & Capabilities** (the project ships with an empty team — you must set your own)
3. Build and run on a device with MONEI Pay installed

The SDK is included via Swift Package Manager (auto-resolved on first build).

## How It Works

### 1. Get an Auth Token

Your backend calls the MONEI API to generate a POS auth token:

```bash
curl -X POST https://api.monei.com/v1/pos/auth-token \
  -H "Authorization: YOUR_API_KEY" \
  -H "Content-Type: application/json"
```

### 2. Accept Payment

```swift
import MoneiPaySDK

let result = try await MoneiPay.acceptPayment(
    token: "eyJ...",              // raw JWT from your backend
    amount: 1500,                 // cents (15.00 EUR)
    callbackScheme: "my-app"      // your registered URL scheme
)

print(result.transactionId)       // "txn_abc123"
print(result.cardBrand)           // "visa"
```

### 3. Wire the Callback Handler

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

### Required Info.plist Configuration

```xml
<!-- Register your callback URL scheme -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>merchant-demo</string>
        </array>
    </dict>
</array>

<!-- Required for canOpenURL to check if MONEI Pay is installed -->
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>monei-pay</string>
</array>
```

## Project Structure

```
MerchantDemo/
├── MerchantDemoApp.swift   # App entry point + SDK callback handler
├── ContentView.swift       # UI: token input, amount, pay button, result display
├── Info.plist              # URL scheme registration
└── Assets.xcassets/        # App icons and colors
```
