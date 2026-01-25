import SwiftUI

// MARK: - ICloudSettingsView

struct ICloudSettingsView: View {
    // MARK: Internal

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

    // MARK: Private

    @StateObject private var monitor = ICloudMonitor()
}

// MARK: - LoFiSettingsView

struct LoFiSettingsView: View {
    // MARK: Internal

    var body: some View {
        List {
            if isConfigured {
                configuredSection
            } else {
                setupSection
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Ham2K LoFi")
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

    @State private var callsign = ""
    @State private var email = ""
    @State private var isConfigured = false
    @State private var isLinked = false
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var statusMessage = ""

    private let lofiClient = LoFiClient()

    @ViewBuilder
    private var configuredSection: some View {
        Section {
            HStack {
                Label(
                    isLinked ? "Connected" : "Pending",
                    systemImage: isLinked ? "checkmark.circle.fill" : "clock"
                )
                .foregroundStyle(isLinked ? .green : .orange)
                Spacer()
                if let call = lofiClient.getCallsign() {
                    Text(call)
                        .foregroundStyle(.secondary)
                }
            }

            if !isLinked {
                Text("Check your email to confirm the device link")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("I've confirmed the email") {
                    Task { await confirmLinked() }
                }

                Button("Resend confirmation email") {
                    Task { await resendLinkEmail() }
                }
            }
        } header: {
            Text("Status")
        }

        Section {
            Button("Logout", role: .destructive) {
                logout()
            }
        }
    }

    @ViewBuilder
    private var setupSection: some View {
        Section {
            TextField("Callsign", text: $callsign)
                .textContentType(.username)
                .textInputAutocapitalization(.characters)

            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
        } header: {
            Text("Setup")
        } footer: {
            Text("Your callsign is used to access your LoFi account. Email is for device verification.")
        }

        Section {
            Button {
                Task { await setupAndRegister() }
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Connect to LoFi")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(callsign.isEmpty || email.isEmpty || isLoading)
        }
    }

    private func checkStatus() async {
        isConfigured = lofiClient.isConfigured
        isLinked = lofiClient.isLinked

        if let existingCallsign = lofiClient.getCallsign() {
            callsign = existingCallsign
        }
        if let existingEmail = lofiClient.getEmail() {
            email = existingEmail
        }
    }

    private func setupAndRegister() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await lofiClient.configure(callsign: callsign, email: email)
            let registration = try await lofiClient.register()
            statusMessage = "Registered as \(registration.account.call)"

            try await lofiClient.linkDevice(email: email)
            statusMessage = "Check your email to confirm the device"

            await checkStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func confirmLinked() async {
        do {
            try await lofiClient.markAsLinked()
            await checkStatus()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func resendLinkEmail() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await lofiClient.linkDevice(email: email)
            statusMessage = "Confirmation email sent"
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func logout() {
        Task {
            try? await lofiClient.clearCredentials()
            await checkStatus()
        }
    }
}
