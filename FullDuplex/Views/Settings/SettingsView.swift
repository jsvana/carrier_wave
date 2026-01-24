import SwiftData
import SwiftUI

struct SettingsMainView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var potaAuth: POTAAuthService

    @State private var showingPOTALogin = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingClearAllConfirmation = false
    @State private var dedupeTimeWindow = 5
    @State private var isDeduplicating = false
    @State private var showingDedupeResult = false
    @State private var dedupeResultMessage = ""

    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("readOnlyMode") private var readOnlyMode = false

    private let lofiClient = LoFiClient()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // QRZ
                    NavigationLink {
                        QRZSettingsView()
                    } label: {
                        Label("QRZ Logbook", systemImage: "globe")
                    }

                    // POTA
                    if let token = potaAuth.currentToken, !token.isExpired {
                        HStack {
                            Label("POTA", systemImage: "leaf")
                            Spacer()
                            if let callsign = token.callsign {
                                Text(callsign)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Logout", role: .destructive) {
                                potaAuth.logout()
                            }
                        }
                    } else {
                        Button {
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
                        } label: {
                            HStack {
                                Label("POTA", systemImage: "leaf")
                                Spacer()
                                Text("Connect")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // LoFi
                    NavigationLink {
                        LoFiSettingsView()
                    } label: {
                        Label("Ham2K LoFi", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    // iCloud
                    NavigationLink {
                        ICloudSettingsView()
                    } label: {
                        Label("iCloud Folder", systemImage: "icloud")
                    }
                } header: {
                    Text("Sync Sources")
                }

                Section {
                    Stepper(
                        "Time window: \(dedupeTimeWindow) min", value: $dedupeTimeWindow, in: 1...15
                    )

                    Button {
                        Task { await runDeduplication() }
                    } label: {
                        if isDeduplicating {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("Scanning...")
                            }
                        } else {
                            Text("Find & Merge Duplicates")
                        }
                    }
                    .disabled(isDeduplicating)
                } header: {
                    Text("Deduplication")
                } footer: {
                    Text(
                        "Find QSOs with same callsign, band, and mode within \(dedupeTimeWindow) minutes and merge them."
                    )
                }

                Section {
                    Button("Clear All QSOs", role: .destructive) {
                        showingClearAllConfirmation = true
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Permanently delete all QSOs from this device")
                }

                Section {
                    Toggle("Debug Mode", isOn: $debugMode)

                    if debugMode {
                        Toggle("Read-Only Mode", isOn: $readOnlyMode)

                        NavigationLink {
                            SyncDebugView()
                        } label: {
                            Label("Sync Debug Log", systemImage: "doc.text.magnifyingglass")
                        }
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    if debugMode && readOnlyMode {
                        Text(
                            "Read-only mode: uploads disabled. Downloads and local changes still work."
                        )
                    } else {
                        Text("Shows individual sync buttons on service cards and debug tools")
                    }
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
            .sheet(isPresented: $showingPOTALogin) {
                POTALoginSheet(authService: potaAuth)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .alert("Clear All QSOs?", isPresented: $showingClearAllConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    Task { await clearAllQSOs() }
                }
            } message: {
                Text(
                    "This will permanently delete all QSOs from this device. This cannot be undone."
                )
            }
            .alert("Deduplication Complete", isPresented: $showingDedupeResult) {
                Button("OK") {}
            } message: {
                Text(dedupeResultMessage)
            }
        }
    }

    private func clearAllQSOs() async {
        do {
            // Delete all ServicePresence records first (due to relationships)
            let presenceDescriptor = FetchDescriptor<ServicePresence>()
            let allPresence = try modelContext.fetch(presenceDescriptor)
            for presence in allPresence {
                modelContext.delete(presence)
            }

            // Delete all QSOs
            let qsoDescriptor = FetchDescriptor<QSO>()
            let allQSOs = try modelContext.fetch(qsoDescriptor)
            for qso in allQSOs {
                modelContext.delete(qso)
            }

            try modelContext.save()

            // Reset LoFi sync timestamp so QSOs can be re-downloaded
            await lofiClient.resetSyncTimestamp()
        } catch {
            errorMessage = "Failed to clear QSOs: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func runDeduplication() async {
        isDeduplicating = true
        defer { isDeduplicating = false }

        do {
            let service = DeduplicationService(modelContext: modelContext)
            let result = try await service.findAndMergeDuplicates(
                timeWindowMinutes: dedupeTimeWindow)

            if result.duplicateGroupsFound == 0 {
                dedupeResultMessage = "No duplicates found."
            } else {
                dedupeResultMessage =
                    "Found \(result.duplicateGroupsFound) duplicate groups.\nMerged \(result.qsosMerged) QSOs, removed \(result.qsosRemoved) duplicates."
            }
            showingDedupeResult = true
        } catch {
            errorMessage = "Deduplication failed: \(error.localizedDescription)"
            showingError = true
        }
    }
}

struct QRZApiKeySheet: View {
    @Binding var apiKey: String
    @Binding var callsign: String?
    @Binding var isAuthenticated: Bool
    @Binding var errorMessage: String
    @Binding var showingError: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var isValidating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(
                        "Enter your QRZ Logbook API key. You can find this in your QRZ logbook settings."
                    )
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

struct QRZSettingsView: View {
    @State private var isAuthenticated = false
    @State private var callsign: String?
    @State private var showingLogin = false
    @State private var apiKey = ""
    @State private var errorMessage = ""
    @State private var showingError = false

    private let qrzClient = QRZClient()

    var body: some View {
        List {
            if isAuthenticated {
                Section {
                    HStack {
                        Label(
                            "Connected",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                        Spacer()
                        if let callsign = callsign {
                            Text(callsign)
                                .foregroundStyle(.secondary)
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
            } else {
                Section {
                    Text("Connect your QRZ Logbook to sync QSOs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button("Connect to QRZ") {
                        showingLogin = true
                    }
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Requires QRZ XML Logbook Data subscription.")
                }

                Section {
                    Link(
                        destination: URL(
                            string:
                                "https://shop.qrz.com/collections/subscriptions/products/xml-logbook-data-subscription-1-year"
                        )!
                    ) {
                        Label("Get QRZ Subscription", systemImage: "arrow.up.right.square")
                    }
                }
            }
        }
        .navigationTitle("QRZ Logbook")
        .sheet(isPresented: $showingLogin) {
            QRZApiKeySheet(
                apiKey: $apiKey,
                callsign: $callsign,
                isAuthenticated: $isAuthenticated,
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

struct LoFiSettingsView: View {
    @State private var callsign = ""
    @State private var email = ""
    @State private var isConfigured = false
    @State private var isLinked = false
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var statusMessage = ""

    private let lofiClient = LoFiClient()

    var body: some View {
        List {
            if isConfigured {
                Section {
                    HStack {
                        Label(
                            isLinked ? "Connected" : "Pending",
                            systemImage: isLinked ? "checkmark.circle.fill" : "clock"
                        )
                        .foregroundStyle(isLinked ? .green : .orange)
                        Spacer()
                        if let callsign = lofiClient.getCallsign() {
                            Text(callsign)
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
            } else {
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
                    Text(
                        "Your callsign is used to access your LoFi account. Email is used for device verification."
                    )
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
