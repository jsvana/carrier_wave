import SwiftUI

// MARK: - QRZApiKeySheet

struct QRZApiKeySheet: View {
    // MARK: Internal

    @Binding var apiKey: String
    @Binding var callsign: String?
    @Binding var isAuthenticated: Bool
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your QRZ Logbook API key from your QRZ logbook settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Link(destination: URL(string: "https://logbook.qrz.com/logbook")!) {
                        Label("Get API key from QRZ Logbook", systemImage: "arrow.up.right.square")
                    }

                    TextField("API Key", text: $apiKey)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        Task { await validateAndSave() }
                    } label: {
                        if isValidating {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                }
            }
            .navigationTitle("QRZ API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var isValidating = false

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            let client = QRZClient()
            let status = try await client.validateApiKey(apiKey)
            try await client.saveApiKey(apiKey)
            try await client.saveCallsign(status.callsign)
            callsign = status.callsign
            isAuthenticated = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

// MARK: - QRZSettingsView

struct QRZSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            if isAuthenticated {
                Section {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        if let callsign {
                            Text(callsign).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Status") }

                Section { Button("Logout", role: .destructive) { logout() } }
            } else {
                Section {
                    Text("Connect your QRZ Logbook to sync QSOs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Connect to QRZ") { showingLogin = true }
                } header: { Text("Setup") }
                    footer: { Text("Requires QRZ XML Logbook Data subscription.") }

                Section {
                    Link(
                        destination: URL(
                            string: "https://shop.qrz.com/collections/subscriptions/products/" +
                                "xml-logbook-data-subscription-1-year")!
                    ) {
                        Label("Get QRZ Subscription", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle("QRZ Logbook")
        .sheet(isPresented: $showingLogin) {
            QRZApiKeySheet(
                apiKey: $apiKey, callsign: $callsign, isAuthenticated: $isAuthenticated,
                errorMessage: $errorMessage, showingError: $showingError
            )
        }
        .alert("Error", isPresented: $showingError) { Button("OK") {} }
        message: { Text(errorMessage) }
        .task { await checkStatus() }
    }

    // MARK: Private

    @State private var isAuthenticated = false
    @State private var callsign: String?
    @State private var showingLogin = false
    @State private var apiKey = ""
    @State private var errorMessage = ""
    @State private var showingError = false

    private let qrzClient = QRZClient()

    private func checkStatus() async {
        isAuthenticated = await qrzClient.hasApiKey()
        callsign = await qrzClient.getCallsign()
    }

    private func logout() {
        Task {
            await qrzClient.logout()
            await checkStatus()
        }
    }
}

// MARK: - POTASettingsView

struct POTASettingsView: View {
    // MARK: Internal

    @ObservedObject var potaAuth: POTAAuthService

    var body: some View {
        List {
            if let token = potaAuth.currentToken, !token.isExpired {
                Section {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        if let callsign = token.callsign {
                            Text(callsign).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Status") }

                Section { Button("Logout", role: .destructive) { potaAuth.logout() } }
            } else {
                Section {
                    Text("Connect your POTA account to sync activations and hunter QSOs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Connect to POTA") {
                        showingLogin = true
                        Task {
                            do {
                                _ = try await potaAuth.authenticate()
                                showingLogin = false
                            } catch {
                                showingLogin = false
                                errorMessage = error.localizedDescription
                                showingError = true
                            }
                        }
                    }
                } header: { Text("Setup") }

                Section {
                    Link(destination: URL(string: "https://pota.app")!) {
                        Label("Visit POTA Website", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle("POTA")
        .sheet(isPresented: $showingLogin) {
            POTALoginSheet(authService: potaAuth)
        }
        .alert("Error", isPresented: $showingError) { Button("OK") {} }
        message: { Text(errorMessage) }
    }

    // MARK: Private

    @State private var showingLogin = false
    @State private var showingError = false
    @State private var errorMessage = ""
}
