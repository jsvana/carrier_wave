// POTA credentials entry view for auto-login
//
// Allows users to store their POTA login credentials securely
// for automatic authentication without manual WebView interaction.

import SwiftUI

// MARK: - POTACredentialsView

struct POTACredentialsView: View {
    // MARK: Internal

    @ObservedObject var authService: POTAAuthService

    var body: some View {
        Form {
            Section {
                TextField("Email", text: $username)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()

                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("POTA Login Credentials")
            } footer: {
                Text("These credentials will be used to automatically log in to POTA.")
            }

            Section {
                Button {
                    saveAndLogin()
                } label: {
                    if isSaving {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Logging in...")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Save & Login")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(username.isEmpty || password.isEmpty || isSaving)
            }

            if hasStoredCredentials {
                Section {
                    Button("Clear Saved Credentials", role: .destructive) {
                        clearCredentials()
                    }
                }
            }

            Section {
                Text("Credentials are stored securely in your device's Keychain.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("POTA Credentials")
        .onAppear(perform: loadExistingCredentials)
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Successfully logged in to POTA!")
        }
    }

    // MARK: Private

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var hasStoredCredentials = false

    private let keychain = KeychainHelper.shared

    private func loadExistingCredentials() {
        // Load existing username if saved (don't load password for security)
        if let savedUsername = try? keychain.readString(for: KeychainHelper.Keys.potaUsername) {
            username = savedUsername
            hasStoredCredentials = true
        }
    }

    private func saveAndLogin() {
        isSaving = true

        Task {
            do {
                // Save credentials to Keychain
                try keychain.save(username, for: KeychainHelper.Keys.potaUsername)
                try keychain.save(password, for: KeychainHelper.Keys.potaPassword)

                // Attempt login with stored credentials
                _ = try await authService.performHeadlessLogin(
                    username: username, password: password
                )

                await MainActor.run {
                    isSaving = false
                    hasStoredCredentials = true
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func clearCredentials() {
        try? keychain.delete(for: KeychainHelper.Keys.potaUsername)
        try? keychain.delete(for: KeychainHelper.Keys.potaPassword)
        username = ""
        password = ""
        hasStoredCredentials = false
    }
}
