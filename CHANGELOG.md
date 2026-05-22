# Changelog

# [1.1.0](https://github.com/MONEI/monei-pay-ios-sdk/compare/v1.0.0...v1.1.0) (2026-05-22)


### Features

* forward orderId and transactionType to deep-link query items ([5d2522c](https://github.com/MONEI/monei-pay-ios-sdk/commit/5d2522c1f9e8326771dc19c3f995073b2f045359))

# [1.0.0](https://github.com/MONEI/monei-pay-ios-sdk/compare/v0.2.3...v1.0.0) (2026-05-22)


### Features

* v1.0 rename callbackScheme to completeScheme, add callbackUrl, expand error surface ([882f2a7](https://github.com/MONEI/monei-pay-ios-sdk/commit/882f2a7a2ae08c54118064297cb8b37bfac607f9))

## [1.0.0](https://github.com/MONEI/monei-pay-ios-sdk/compare/v0.2.3...v1.0.0) (2026-05-21)


### BREAKING CHANGES

* `MoneiPay.acceptPayment(...)` — parameter `callbackScheme` is now `completeScheme`. Migrate by renaming the argument label at every call site.
* `MoneiPay.handleCallback(url:)` is now `MoneiPay.handleCompleteRedirect(url:)`. Update your `.onOpenURL { ... }` / `application(_:open:options:)` hook.
* Deep-link wire format: the SDK now emits `complete_url` (was `callback`) and the new optional `callback_url` query items when building the MONEI Pay URL.


### Features

* add `callbackUrl: String?` to `acceptPayment(...)` — strict HTTPS endpoint for the trusted signed webhook channel (HMAC `MONEI-Signature`). Pair this with `completeScheme` for production: webhook = trusted fulfillment, complete-redirect = UX only.
* expand `MoneiPayError` to cover the full set of error codes returned by the MONEI Pay app: `tokenExpired`, `invalidToken`, `notAuthenticated`, `accountNotConfigured`, plus typed mapping for `INVALID_AMOUNT`, `INVALID_CALLBACK_URL`, `INVALID_COMPLETE_URL` via `invalidParameters`.

## [0.2.3](https://github.com/MONEI/monei-pay-ios-sdk/compare/v0.2.2...v0.2.3) (2026-05-13)


### Features

* **example:** support master account flow via MONEI-Account-ID and User-Agent ([ce24373](https://github.com/MONEI/monei-pay-ios-sdk/commit/ce243734ea1e0644b2464e0f6e7e1ebe99a9baad))

## [0.2.2](https://github.com/MONEI/monei-pay-ios-sdk/compare/v0.2.1...v0.2.2) (2026-03-30)


### Bug Fixes

* **ci:** CocoaPods publish uses default Xcode + husky commitlint ([04ce55e](https://github.com/MONEI/monei-pay-ios-sdk/commit/04ce55e4d58957de5a8ad4bb02d9f11dc97e22b0))

## [0.2.1](https://github.com/MONEI/monei-pay-ios-sdk/compare/v0.2.0...v0.2.1) (2026-03-30)
