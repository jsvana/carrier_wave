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
            try client.saveApiKey(apiKey)
            try client.saveCallsign(status.callsign)
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
                } header: {
                    Text("Status")
                }

                Section { Button("Logout", role: .destructive) { logout() } }
            } else {
                Section {
                    Text("Connect your QRZ Logbook to sync QSOs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Connect to QRZ") { showingLogin = true }
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Requires QRZ XML Logbook Data subscription.")
                }

                Section {
                    Link(
                        destination: URL(
                            string: "https://shop.qrz.com/collections/subscriptions/products/"
                                + "xml-logbook-data-subscription-1-year")!
                    ) {
                        Label("Get QRZ Subscription", systemImage: "arrow.up.right.square")
                    }
                }
            }

            if debugMode, isAuthenticated {
                Section {
                    Button {
                        Task { await forceRedownload() }
                    } label: {
                        if isRedownloading {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Re-downloading...")
                            }
                        } else {
                            Text("Force Re-download All QSOs")
                        }
                    }
                    .disabled(isRedownloading)

                    if let result = redownloadResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text(
                        "Re-fetches all QSOs from QRZ and updates existing records with fresh parsed values."
                    )
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
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .onAppear { checkStatus() }
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false
    @EnvironmentObject private var syncService: SyncService
    @State private var isAuthenticated = false
    @State private var callsign: String?
    @State private var showingLogin = false
    @State private var apiKey = ""
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var isRedownloading = false
    @State private var redownloadResult: String?

    private let qrzClient = QRZClient()

    private func checkStatus() {
        isAuthenticated = qrzClient.hasApiKey()
        callsign = qrzClient.getCallsign()
    }

    private func logout() {
        qrzClient.logout()
        checkStatus()
    }

    private func forceRedownload() async {
        isRedownloading = true
        redownloadResult = nil
        defer { isRedownloading = false }

        do {
            let result = try await syncService.forceRedownloadFromQRZ()
            redownloadResult = "Updated \(result.updated), Created \(result.created)"
        } catch {
            redownloadResult = "Error: \(error.localizedDescription)"
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

                    HStack {
                        Text("Session Expires")
                        Spacer()
                        Text(token.expiresAt, style: .relative)
                            .foregroundStyle(token.isExpiringSoon() ? .orange : .secondary)
                    }
                } header: {
                    Text("Status")
                } footer: {
                    if token.isExpiringSoon() {
                        Text("Session expiring soon. It will auto-refresh on next sync.")
                    }
                }

                Section {
                    NavigationLink("Login Credentials") {
                        POTACredentialsView(authService: potaAuth)
                    }
                } footer: {
                    Text("Update your saved credentials for automatic login.")
                }

                Section { Button("Logout", role: .destructive) { potaAuth.logout() } }
            } else {
                Section {
                    Text("Connect your POTA account to sync activations and hunter QSOs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink("Save Credentials & Login") {
                        POTACredentialsView(authService: potaAuth)
                    }

                    Button("Manual Login (WebView)") {
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
                } header: {
                    Text("Setup")
                } footer: {
                    Text(
                        "Save your credentials for automatic login, or use manual login if you prefer."
                    )
                }

                Section {
                    Link(destination: URL(string: "https://pota.app")!) {
                        Label("Visit POTA Website", systemImage: "arrow.up.right.square")
                    }
                }
            }

            if debugMode, potaAuth.isAuthenticated {
                Section {
                    Button {
                        Task { await forceRedownload() }
                    } label: {
                        if isRedownloading {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Re-downloading...")
                            }
                        } else {
                            Text("Force Re-download All QSOs")
                        }
                    }
                    .disabled(isRedownloading)

                    if let result = redownloadResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Debug")
                } footer: {
                    Text(
                        "Re-fetches all QSOs from POTA and updates existing records with fresh parsed values."
                    )
                }
            }
        }
        .navigationTitle("POTA")
        .sheet(isPresented: $showingLogin) {
            POTALoginSheet(authService: potaAuth)
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: Private

    @AppStorage("debugMode") private var debugMode = false
    @EnvironmentObject private var syncService: SyncService
    @State private var showingLogin = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var isRedownloading = false
    @State private var redownloadResult: String?

    private func forceRedownload() async {
        isRedownloading = true
        redownloadResult = nil
        defer { isRedownloading = false }

        do {
            let result = try await syncService.forceRedownloadFromPOTA()
            redownloadResult = "Updated \(result.updated), Created \(result.created)"
        } catch {
            redownloadResult = "Error: \(error.localizedDescription)"
        }
    }
}
