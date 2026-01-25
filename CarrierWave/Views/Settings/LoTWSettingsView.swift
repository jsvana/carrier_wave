import SwiftUI

// MARK: - LoTWSettingsView

struct LoTWSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            if isAuthenticated {
                Section {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text(username)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Status")
                }

                Section {
                    Button("Logout", role: .destructive) {
                        logout()
                    }
                }
            } else {
                Section {
                    Text("Connect your LoTW account to import QSOs and QSL confirmations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Connect to LoTW") {
                        showingLogin = true
                    }
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Uses your LoTW website username and password.")
                }

                Section {
                    Link(destination: URL(string: "https://lotw.arrl.org")!) {
                        Label("Visit LoTW Website", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle("LoTW")
        .sheet(isPresented: $showingLogin) {
            LoTWLoginSheet(
                isAuthenticated: $isAuthenticated,
                storedUsername: $username,
                errorMessage: $errorMessage,
                showingError: $showingError
            )
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .task {
            await checkStatus()
        }
    }

    // MARK: Private

    @State private var isAuthenticated = false
    @State private var username = ""
    @State private var showingLogin = false
    @State private var errorMessage = ""
    @State private var showingError = false

    private let lotwClient = LoTWClient()

    private func checkStatus() async {
        isAuthenticated = await lotwClient.hasCredentials()
        if isAuthenticated {
            if let creds = try? await lotwClient.getCredentials() {
                username = creds.username
            }
        }
    }

    private func logout() {
        Task {
            await lotwClient.clearCredentials()
            await checkStatus()
        }
    }
}

// MARK: - LoTWLoginSheet

struct LoTWLoginSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var isAuthenticated: Bool
    @Binding var storedUsername: String
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    @State private var username = ""
    @State private var password = ""
    @State private var isValidating = false

    private let lotwClient = LoTWClient()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Enter your LoTW website login credentials.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)
                        .textContentType(.password)
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
                    .disabled(username.isEmpty || password.isEmpty || isValidating)
                }
            }
            .navigationTitle("LoTW Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func validateAndSave() async {
        isValidating = true
        defer { isValidating = false }

        do {
            try await lotwClient.testCredentials(username: username, password: password)
            try await lotwClient.saveCredentials(username: username, password: password)
            storedUsername = username
            isAuthenticated = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
