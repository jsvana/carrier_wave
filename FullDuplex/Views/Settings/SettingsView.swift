import SwiftUI
import SwiftData

struct SettingsMainView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var potaAuth = POTAAuthService()

    @State private var qrzUsername = ""
    @State private var qrzPassword = ""
    @State private var qrzIsAuthenticated = false
    @State private var showingQRZLogin = false
    @State private var showingPOTALogin = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if qrzIsAuthenticated {
                        HStack {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Logout") {
                                logoutQRZ()
                            }
                            .foregroundStyle(.red)
                        }
                    } else {
                        Button("Login to QRZ") {
                            showingQRZLogin = true
                        }
                    }
                } header: {
                    Text("QRZ Logbook")
                } footer: {
                    Text("Upload your logs to QRZ.com logbook")
                }

                Section {
                    if let token = potaAuth.currentToken, !token.isExpired {
                        HStack {
                            VStack(alignment: .leading) {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                if let callsign = token.callsign {
                                    Text(callsign)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Logout") {
                                potaAuth.logout()
                            }
                            .foregroundStyle(.red)
                        }

                        Text("Token expires: \(token.expiresAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Login to POTA") {
                            showingPOTALogin = true
                            Task {
                                do {
                                    _ = try await potaAuth.authenticate()
                                    showingPOTALogin = false
                                } catch {
                                    showingPOTALogin = false
                                    errorMessage = error.localizedDescription
                                    showingError = true
                                }
                            }
                        }
                    }
                } header: {
                    Text("POTA")
                } footer: {
                    Text("Upload activation logs to Parks on the Air")
                }

                Section {
                    NavigationLink {
                        ICloudSettingsView()
                    } label: {
                        Label("iCloud Folder", systemImage: "icloud")
                    }
                } header: {
                    Text("Import Sources")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingQRZLogin) {
                QRZLoginSheet(
                    username: $qrzUsername,
                    password: $qrzPassword,
                    isAuthenticated: $qrzIsAuthenticated,
                    errorMessage: $errorMessage,
                    showingError: $showingError
                )
            }
            .sheet(isPresented: $showingPOTALogin) {
                POTALoginSheet(authService: potaAuth)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                checkQRZAuth()
            }
        }
    }

    private func checkQRZAuth() {
        do {
            _ = try KeychainHelper.shared.readString(for: KeychainHelper.Keys.qrzSessionKey)
            qrzIsAuthenticated = true
        } catch {
            qrzIsAuthenticated = false
        }
    }

    private func logoutQRZ() {
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.qrzSessionKey)
        try? KeychainHelper.shared.delete(for: KeychainHelper.Keys.qrzUsername)
        qrzIsAuthenticated = false
    }
}

struct QRZLoginSheet: View {
    @Binding var username: String
    @Binding var password: String
    @Binding var isAuthenticated: Bool
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isLoggingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        if isLoggingIn {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Login")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty || isLoggingIn)
                }
            }
            .navigationTitle("QRZ Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func login() async {
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let client = QRZClient()
            _ = try await client.authenticate(username: username, password: password)
            isAuthenticated = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

struct ICloudSettingsView: View {
    @StateObject private var monitor = ICloudMonitor()

    var body: some View {
        List {
            Section {
                if let url = monitor.iCloudContainerURL {
                    VStack(alignment: .leading) {
                        Text("Import Folder")
                            .font(.headline)
                        Text(url.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Create Folder") {
                        monitor.createImportFolderIfNeeded()
                    }
                } else {
                    Text("iCloud is not available")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Place ADIF files in this folder to import them")
            }

            Section {
                Toggle("Monitor for new files", isOn: .constant(monitor.isMonitoring))
                    .disabled(true)
            }
        }
        .navigationTitle("iCloud")
    }
}
