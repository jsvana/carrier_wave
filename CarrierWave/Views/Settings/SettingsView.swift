import SwiftData
import SwiftUI

// MARK: - SettingsMainView

struct SettingsMainView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var potaAuth: POTAAuthService

    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingClearAllConfirmation = false
    @State private var isClearingQSOs = false
    @State private var dedupeTimeWindow = 5
    @State private var isDeduplicating = false
    @State private var showingDedupeResult = false
    @State private var dedupeResultMessage = ""

    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("readOnlyMode") private var readOnlyMode = false
    @AppStorage("bypassPOTAMaintenance") private var bypassPOTAMaintenance = false

    private let lofiClient = LoFiClient()
    private let qrzClient = QRZClient()
    private let hamrsClient = HAMRSClient()
    private let lotwClient = LoTWClient()
    @StateObject private var iCloudMonitor = ICloudMonitor()

    @State private var qrzIsConfigured = false
    @State private var qrzCallsign: String?

    @State private var lotwIsConfigured = false
    @State private var lotwUsername: String?

    @Query(sort: \ChallengeSource.name) private var challengeSources: [ChallengeSource]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // QRZ
                    NavigationLink {
                        QRZSettingsView()
                    } label: {
                        HStack {
                            Label("QRZ Logbook", systemImage: "globe")
                            Spacer()
                            if qrzIsConfigured {
                                if let callsign = qrzCallsign {
                                    Text(callsign)
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Connected")
                            }
                        }
                    }

                    // POTA
                    NavigationLink {
                        POTASettingsView(potaAuth: potaAuth)
                    } label: {
                        HStack {
                            Label("POTA", systemImage: "leaf")
                            Spacer()
                            if let token = potaAuth.currentToken, !token.isExpired {
                                if let callsign = token.callsign {
                                    Text(callsign)
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Logged in")
                            }
                        }
                    }

                    // LoFi
                    NavigationLink {
                        LoFiSettingsView()
                    } label: {
                        HStack {
                            Label("Ham2K LoFi", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            if lofiClient.isConfigured {
                                if let callsign = lofiClient.getCallsign() {
                                    Text(callsign)
                                        .foregroundStyle(.secondary)
                                }
                                if lofiClient.isLinked {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .accessibilityLabel("Connected")
                                } else {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("Pending connection")
                                }
                            }
                        }
                    }

                    // HAMRS
                    NavigationLink {
                        HAMRSSettingsView()
                    } label: {
                        HStack {
                            Label("HAMRS Pro", systemImage: "rectangle.stack")
                            Spacer()
                            if hamrsClient.isConfigured {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Connected")
                            }
                        }
                    }

                    // LoTW
                    NavigationLink {
                        LoTWSettingsView()
                    } label: {
                        HStack {
                            Label("LoTW", systemImage: "envelope.badge.shield.half.filled")
                            Spacer()
                            if lotwIsConfigured {
                                if let username = lotwUsername {
                                    Text(username)
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Connected")
                            }
                        }
                    }

                    // iCloud
                    NavigationLink {
                        ICloudSettingsView()
                    } label: {
                        HStack {
                            Label("iCloud Folder", systemImage: "icloud")
                            Spacer()
                            if iCloudMonitor.iCloudContainerURL != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Available")
                            }
                        }
                    }

                    // Challenges
                    NavigationLink {
                        ChallengesSettingsView()
                    } label: {
                        HStack {
                            Label("Challenges", systemImage: "flag.2.crossed")
                            Spacer()
                            if challengeSources.contains(where: { $0.lastFetched != nil }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .accessibilityLabel("Connected")
                            }
                        }
                    }
                } header: {
                    Text("Sync Sources")
                }

                Section {
                    Stepper(
                        "Time window: \(dedupeTimeWindow) min", value: $dedupeTimeWindow, in: 1 ... 15
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
                        "Find QSOs with same callsign, band, and mode within \(dedupeTimeWindow) min and merge."
                    )
                }

                Section {
                    Toggle("Debug Mode", isOn: $debugMode)

                    if debugMode {
                        Toggle("Read-Only Mode", isOn: $readOnlyMode)
                        Toggle("Bypass POTA Maintenance", isOn: $bypassPOTAMaintenance)

                        NavigationLink {
                            SyncDebugView()
                        } label: {
                            Label("Sync Debug Log", systemImage: "doc.text.magnifyingglass")
                        }

                        Button(role: .destructive) {
                            showingClearAllConfirmation = true
                        } label: {
                            if isClearingQSOs {
                                HStack {
                                    ProgressView()
                                    Text("Clearing...")
                                }
                            } else {
                                Text("Clear All QSOs")
                            }
                        }
                        .disabled(isClearingQSOs)
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    if debugMode, bypassPOTAMaintenance {
                        Text("POTA maintenance window bypass enabled. Uploads allowed 24/7.")
                    } else if debugMode, readOnlyMode {
                        Text(
                            "Read-only mode: uploads disabled. Downloads and local changes still work."
                        )
                    } else {
                        Text("Shows individual sync buttons on service cards and debug tools")
                    }
                }

                Section {
                    NavigationLink {
                        ExternalDataView()
                    } label: {
                        Label("External Data", systemImage: "arrow.down.circle")
                    }
                } header: {
                    Text("Data")
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.8.0")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        AttributionsView()
                    } label: {
                        Label("Attributions", systemImage: "heart")
                    }
                } header: {
                    Text("About")
                }
            }
            .onAppear {
                loadServiceStatus()
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
        isClearingQSOs = true
        defer { isClearingQSOs = false }

        do {
            // Use batch deletion - cascade delete rule handles ServicePresence
            try modelContext.delete(model: QSO.self)
            try modelContext.save()

            // Reset LoFi sync timestamp so QSOs can be re-downloaded
            lofiClient.resetSyncTimestamp()
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
                dedupeResultMessage = """
                Found \(result.duplicateGroupsFound) duplicate groups.
                Merged \(result.qsosMerged) QSOs, removed \(result.qsosRemoved) duplicates.
                """
            }
            showingDedupeResult = true
        } catch {
            errorMessage = "Deduplication failed: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func loadServiceStatus() {
        qrzIsConfigured = qrzClient.hasApiKey()
        qrzCallsign = qrzClient.getCallsign()

        lotwIsConfigured = lotwClient.hasCredentials()
        if lotwIsConfigured {
            if let creds = try? lotwClient.getCredentials() {
                lotwUsername = creds.username
            }
        }
    }
}

// QRZApiKeySheet, QRZSettingsView, POTASettingsView are in ServiceSettingsViews.swift
// ICloudSettingsView, LoFiSettingsView are in CloudSettingsViews.swift
