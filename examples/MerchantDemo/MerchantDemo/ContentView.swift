import SwiftUI
import MoneiPaySDK

// MARK: - Content View
// Single-screen UI: enter API key + POS ID, fetch token, accept payment.

struct ContentView: View {
    /// MONEI API key (from dashboard)
    @State private var apiKey: String = ""
    /// Point of Sale ID (optional — account's default card present provider used if empty)
    @State private var posId: String = ""
    /// Raw JWT auth token (fetched from API or pasted manually)
    @State private var authToken: String = ""
    /// Amount in cents (e.g. 1500 = 15.00 EUR)
    @State private var amountText: String = ""
    /// Whether MONEI Pay is installed on this device
    @State private var isMoneiPayInstalled: Bool = true
    /// Payment result from the SDK
    @State private var paymentResult: PaymentResult?
    /// Error message if something fails
    @State private var errorMessage: String?
    /// Whether a token fetch or payment is in progress
    @State private var isProcessing: Bool = false
    /// Whether we're fetching a token
    @State private var isFetchingToken: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Credentials
                Section {
                    TextField("MONEI API Key", text: $apiKey)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    TextField("Point of Sale ID (optional)", text: $posId)
                        .font(.system(.caption, design: .monospaced))
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                    Button(action: fetchToken) {
                        if isFetchingToken {
                            ProgressView()
                        } else {
                            Label("Get Token", systemImage: "key")
                        }
                    }
                    .disabled(apiKey.isEmpty || isFetchingToken)
                } header: {
                    Text("Credentials")
                } footer: {
                    Text("Enter your MONEI API key. Point of Sale ID is optional — leave empty to use the account's default card present provider.")
                }

                // MARK: Auth Token (auto-filled or manual)
                if !authToken.isEmpty {
                    Section {
                        Text(authToken)
                            .lineLimit(3)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } header: {
                        HStack {
                            Text("Auth Token")
                            Spacer()
                            Button("Clear") {
                                authToken = ""
                            }
                            .font(.caption)
                        }
                    }
                }

                // MARK: Payment Input
                Section {
                    TextField("Amount in cents (e.g. 1500 = 15.00 EUR)", text: $amountText)
                        .keyboardType(.numberPad)

                    Button(action: acceptPayment) {
                        if isProcessing {
                            ProgressView()
                        } else {
                            Label("Accept Payment", systemImage: "creditcard.and.123")
                        }
                    }
                    .disabled(amountText.isEmpty || authToken.isEmpty || !isMoneiPayInstalled || isProcessing)
                } header: {
                    Text("New Payment")
                } footer: {
                    if !isMoneiPayInstalled {
                        Text("MONEI Pay is not installed. Install it from the App Store to accept NFC payments.")
                            .foregroundStyle(.red)
                    }
                }

                // MARK: Payment Result
                if let result = paymentResult {
                    Section("Payment Result") {
                        if result.success {
                            Label("Payment Successful", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Payment Failed", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }

                        LabeledContent("Transaction ID", value: result.transactionId)

                        if let amount = result.amount {
                            LabeledContent("Amount (cents)", value: "\(amount)")
                        }
                        if let brand = result.cardBrand {
                            LabeledContent("Card Brand", value: brand)
                        }
                        if let masked = result.maskedCardNumber {
                            LabeledContent("Card Number", value: masked)
                        }
                    }
                }

                // MARK: Error
                if let errorMessage {
                    Section("Error") {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Merchant Demo")
        }
        .onAppear(perform: checkMoneiPayInstalled)
    }

    // MARK: - Actions

    private func checkMoneiPayInstalled() {
        guard let url = URL(string: "monei-pay://") else { return }
        isMoneiPayInstalled = UIApplication.shared.canOpenURL(url)
    }

    /// Fetch POS auth token from MONEI API using the API key.
    private func fetchToken() {
        errorMessage = nil
        isFetchingToken = true

        Task {
            do {
                let url = URL(string: "https://api.monei.com/v1/pos/auth-token")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue(apiKey, forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                var body: [String: String] = [:]
                if !posId.isEmpty { body["pointOfSaleId"] = posId }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }

                if httpResponse.statusCode == 200 {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let token = json["token"] as? String {
                        authToken = token
                    } else {
                        throw NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "Could not parse token"])
                    }
                } else {
                    let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw NSError(domain: "", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(errorBody)"])
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isFetchingToken = false
        }
    }

    /// Accept a payment using the MoneiPay SDK.
    private func acceptPayment() {
        guard let amount = Int(amountText), amount > 0 else { return }

        paymentResult = nil
        errorMessage = nil
        isProcessing = true

        Task {
            do {
                let result = try await MoneiPay.acceptPayment(
                    token: authToken,
                    amount: amount,
                    callbackScheme: "merchant-demo"
                )
                paymentResult = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isProcessing = false
        }
    }
}

#Preview {
    ContentView()
}
