import SwiftData
import SwiftUI
import UIKit

// swiftlint:disable file_length

// MARK: - SettingsMainView

// swiftlint:disable:next type_body_length
struct SettingsMainView: View {
    // MARK: Internal

    @ObservedObject var potaAuth: POTAAuthService
    @Binding var destination: SettingsDestination?

    let tourState: TourState

    /// When true, the view is already inside a navigation context (e.g., "More" tab)
    /// and should not add its own NavigationStack
    var isInNavigationContext: Bool = false

    var body: some View {
        if isInNavigationContext {
            settingsContent
        } else {
            NavigationStack(path: $navigationPath) {
                settingsContent
            }
        }
    }

    // MARK: Private

    @Environment(\.modelContext) private var modelContext

    @State private var navigationPath = NavigationPath()
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingClearAllConfirmation = false
    @State private var isClearingQSOs = false
    @State private var dedupeTimeWindow = 5
    @State private var isDeduplicating = false
    @State private var showingDedupeResult = false
    @State private var dedupeResultMessage = ""
    @State private var isExportingDatabase = false
    @State private var exportedFile: ExportedFile?
    @State private var showingBugReport = false
    @State private var showIntroTour = false
    @State private var showOnboarding = false

    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("readOnlyMode") private var readOnlyMode = false
    @AppStorage("bypassPOTAMaintenance") private var bypassPOTAMaintenance = false

    // Logger settings
    @AppStorage("loggerDefaultMode") private var defaultMode = "CW"
    @AppStorage("loggerSkipWizard") private var skipWizard = false
    @AppStorage("loggerShowActivityPanel") private var showActivityPanel = true
    @AppStorage("loggerShowLicenseWarnings") private var showLicenseWarnings = true
    @AppStorage("loggerKeepScreenOn") private var keepScreenOn = true
    @AppStorage("loggerQuickLogMode") private var quickLogMode = false
    @AppStorage("potaAutoSpotEnabled") private var potaAutoSpotEnabled = false
    @AppStorage("loggerAutoModeSwitch") private var autoModeSwitch = true
    @AppStorage("callsignNotesDisplayMode") private var notesDisplayMode = "emoji"

    // Logger visible fields
    @AppStorage("loggerShowNotes") private var showNotes = false
    @AppStorage("loggerShowTheirGrid") private var showTheirGrid = false
    @AppStorage("loggerShowTheirPark") private var showTheirPark = false
    @AppStorage("loggerShowOperator") private var showOperator = false

    @StateObject private var iCloudMonitor = ICloudMonitor()
    @State private var qrzIsConfigured = false
    @State private var qrzCallsign: String?

    @State private var qrzCallbookIsConfigured = false

    @State private var lotwIsConfigured = false
    @State private var lotwUsername: String?

    @State private var userProfile: UserProfile?

    @Query(sort: \ChallengeSource.name) private var challengeSources: [ChallengeSource]

    private let lofiClient = LoFiClient()
    private let qrzClient = QRZClient()
    private let hamrsClient = HAMRSClient()
    private let lotwClient = LoTWClient()

    private var settingsContent: some View {
        List {
            profileSection
            tabsSection
            loggerSection
            potaSection
            SyncSourcesSection(
                potaAuth: potaAuth,
                lofiClient: lofiClient,
                qrzClient: qrzClient,
                hamrsClient: hamrsClient,
                lotwClient: lotwClient,
                iCloudMonitor: iCloudMonitor,
                qrzIsConfigured: qrzIsConfigured,
                qrzCallsign: qrzCallsign,
                lotwIsConfigured: lotwIsConfigured,
                lotwUsername: lotwUsername,
                challengeSources: challengeSources,
                tourState: tourState
            )
            deduplicationSection
            developerSection
            dataSection
            aboutSection
        }
        .navigationDestination(for: SettingsDestination.self) { dest in
            switch dest {
            case .qrz:
                QRZSettingsView()
            case .pota:
                POTASettingsView(potaAuth: potaAuth, tourState: tourState)
            case .lofi:
                LoFiSettingsView(tourState: tourState)
            case .hamrs:
                HAMRSSettingsView()
            case .lotw:
                LoTWSettingsView()
            case .icloud:
                ICloudSettingsView()
            }
        }
        .onAppear {
            loadServiceStatus()
        }
        .task(id: destination) {
            // Handle deep link - task restarts when destination changes
            guard let dest = destination else {
                return
            }
            // Small delay to ensure NavigationStack is ready after tab switch
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            navigationPath.append(dest)
            destination = nil
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
        .sheet(
            item: $exportedFile,
            onDismiss: { isExportingDatabase = false },
            content: { file in ShareSheet(activityItems: [file.url]) }
        )
        .sheet(isPresented: $showingBugReport) {
            BugReportView(potaAuth: potaAuth, iCloudMonitor: iCloudMonitor)
        }
        .fullScreenCover(isPresented: $showIntroTour) {
            IntroTourView(tourState: tourState)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(tourState: tourState, potaAuth: potaAuth)
        }
        .onChange(of: showOnboarding) { _, isShowing in
            // Reload profile after onboarding completes
            if !isShowing {
                userProfile = UserProfileService.shared.getProfile()
            }
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section {
            NavigationLink {
                AboutMeView {
                    showOnboarding = true
                }
            } label: {
                HStack {
                    if let profile = userProfile {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.callsign)
                                .font(.headline)
                                .monospaced()
                            if let name = profile.fullName {
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let licenseClass = profile.licenseClass {
                            Text(licenseClass.abbreviation)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    } else {
                        Label("Set Up Profile", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
        } header: {
            Text("My Profile")
        }
    }

    private var tabsSection: some View {
        Section {
            NavigationLink {
                TabConfigurationView()
            } label: {
                HStack {
                    Label("Tab Bar", systemImage: "square.grid.2x2")
                    Spacer()
                    let visibleCount = TabConfiguration.visibleTabs().filter { $0 != .more }.count
                    Text("\(visibleCount) in tab bar")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Navigation")
        } footer: {
            Text("Choose which tabs appear in the tab bar. Hidden tabs are accessible from More.")
        }
    }

    private var loggerSection: some View {
        Section {
            // License class (read-only, from profile)
            if let profile = userProfile, let licenseClass = profile.licenseClass {
                HStack {
                    Text("License Class")
                    Spacer()
                    Text(licenseClass.displayName)
                        .foregroundStyle(.secondary)
                }

                Toggle("Show band privilege warnings", isOn: $showLicenseWarnings)
            }

            Picker("Default Mode", selection: $defaultMode) {
                ForEach(["CW", "SSB", "FT8", "FT4", "RTTY"], id: \.self) { mode in
                    Text(mode).tag(mode)
                }
            }

            Toggle("Skip session wizard", isOn: $skipWizard)
            Toggle("Show frequency activity", isOn: $showActivityPanel)
            Toggle("Keep screen on", isOn: $keepScreenOn)
            Toggle("Quick Log Mode", isOn: $quickLogMode)
            Toggle("Auto-switch mode for frequency", isOn: $autoModeSwitch)

            Picker("Notes display", selection: $notesDisplayMode) {
                Text("Emoji").tag("emoji")
                Text("Source names").tag("sources")
            }

            DisclosureGroup("Always visible fields") {
                Toggle("Notes", isOn: $showNotes)
                Toggle("Their Grid", isOn: $showTheirGrid)
                Toggle("Their Park", isOn: $showTheirPark)
                Toggle("Operator", isOn: $showOperator)
            }
        } header: {
            Text("Logger")
        } footer: {
            Text(
                "Quick Log Mode disables animations for faster QSO entry. "
                    + "Keep screen on prevents device sleep during sessions. "
                    + "Always visible fields appear without tapping \"More\"."
            )
        }
    }

    private var potaSection: some View {
        Section {
            Toggle("Auto-spot every 10 minutes", isOn: $potaAutoSpotEnabled)
        } header: {
            Text("POTA Activations")
        } footer: {
            Text(
                "When enabled, automatically posts a spot to POTA every 10 minutes "
                    + "during active POTA sessions."
            )
        }
    }

    private var deduplicationSection: some View {
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
                """
                Find QSOs with same callsign, band, and mode within \(dedupeTimeWindow) min \
                and merge. Mode families are treated as equivalent (e.g., PHONE/SSB/USB, \
                DATA/FT8/PSK31).
                """
            )
        }
    }

    private var developerSection: some View {
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
    }

    private var dataSection: some View {
        Section {
            // QRZ Callbook (for callsign lookups)
            NavigationLink {
                QRZCallbookSettingsView()
            } label: {
                HStack {
                    Label("QRZ Callbook", systemImage: "magnifyingglass")
                    Spacer()
                    if qrzCallbookIsConfigured {
                        if let username = try? KeychainHelper.shared.readString(
                            for: KeychainHelper.Keys.qrzCallbookUsername
                        ) {
                            Text(username)
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("Connected")
                    }
                }
            }

            NavigationLink {
                CallsignNotesSettingsView()
            } label: {
                Label("Callsign Notes", systemImage: "note.text")
            }

            NavigationLink {
                ExternalDataView()
            } label: {
                Label("External Data", systemImage: "arrow.down.circle")
            }

            Button {
                isExportingDatabase = true
                Task { await exportDatabase() }
            } label: {
                if isExportingDatabase {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Exporting...")
                    }
                } else {
                    Label("Export SQLite Database", systemImage: "square.and.arrow.up")
                }
            }
            .disabled(isExportingDatabase)
        } header: {
            Text("Data")
        } footer: {
            Text(
                "QRZ Callbook enables callsign lookups (requires QRZ XML subscription). "
                    + "Export creates a backup of the QSO database."
            )
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text("1.14.0")
                    .foregroundStyle(.secondary)
            }

            Link(destination: URL(string: "https://discord.gg/PqubUxWW62")!) {
                Label("Join Discord", systemImage: "bubble.left.and.bubble.right")
            }

            Button {
                showingBugReport = true
            } label: {
                Label("Report a Bug", systemImage: "ant")
            }

            Button {
                tourState.resetForTesting()
                showIntroTour = true
            } label: {
                Label("Show App Tour", systemImage: "questionmark.circle")
            }

            Link(destination: URL(string: "https://discord.gg/ksNb2jAeTR")!) {
                Label("Request a Feature", systemImage: "lightbulb")
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

    @MainActor
    private func exportDatabase() async {
        do {
            try modelContext.save()
            let exportURL = try await DatabaseExporter.export(from: modelContext.container)
            exportedFile = ExportedFile(url: exportURL)
        } catch {
            isExportingDatabase = false
            errorMessage = "Failed to export database: \(error.localizedDescription)"
            showingError = true
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
                timeWindowMinutes: dedupeTimeWindow
            )

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

        qrzCallbookIsConfigured = checkQRZCallbookAuth()

        lotwIsConfigured = lotwClient.hasCredentials()
        if lotwIsConfigured {
            if let creds = try? lotwClient.getCredentials() {
                lotwUsername = creds.username
            }
        }

        userProfile = UserProfileService.shared.getProfile()
    }

    private func checkQRZCallbookAuth() -> Bool {
        (try? KeychainHelper.shared.readString(
            for: KeychainHelper.Keys.qrzCallbookUsername
        )) != nil
            && (try? KeychainHelper.shared.readString(
                for: KeychainHelper.Keys.qrzCallbookPassword
            )) != nil
    }
}

// MARK: - ExportedFile

// QRZApiKeySheet, QRZSettingsView, POTASettingsView are in ServiceSettingsViews.swift
// ICloudSettingsView, LoFiSettingsView are in CloudSettingsViews.swift

struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - DatabaseExporter

enum DatabaseExporter {
    enum ExportError: LocalizedError {
        case storeNotFound

        // MARK: Internal

        var errorDescription: String? {
            switch self {
            case .storeNotFound:
                "Could not locate the database file."
            }
        }
    }

    static func export(from container: ModelContainer) async throws -> URL {
        guard let config = container.configurations.first else {
            throw ExportError.storeNotFound
        }
        let storeURL = config.url

        return try await Task.detached(priority: .userInitiated) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestamp = dateFormatter.string(from: Date())
            let exportFilename = "CarrierWave_QSO_Export_\(timestamp).sqlite"

            let tempDir = FileManager.default.temporaryDirectory
            let exportURL = tempDir.appendingPathComponent(exportFilename)

            if FileManager.default.fileExists(atPath: exportURL.path) {
                try FileManager.default.removeItem(at: exportURL)
            }

            try FileManager.default.copyItem(at: storeURL, to: exportURL)

            // Copy WAL and SHM files if they exist for complete export
            for ext in ["wal", "shm"] {
                let sourceURL = storeURL.appendingPathExtension(ext)
                let destURL = exportURL.appendingPathExtension(ext)
                if FileManager.default.fileExists(atPath: sourceURL.path) {
                    if FileManager.default.fileExists(atPath: destURL.path) {
                        try FileManager.default.removeItem(at: destURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destURL)
                }
            }

            return exportURL
        }.value
    }
}

// MARK: - TabConfigurationView

struct TabConfigurationView: View {
    // MARK: Internal

    var body: some View {
        List {
            // Tab Bar section - shows visible tabs
            Section {
                ForEach(tabBarTabs, id: \.self) { tab in
                    tabRow(tab, inTabBar: true)
                }
                .onMove(perform: moveTabBarTab)
            } header: {
                Text("Tab Bar")
            } footer: {
                if tabBarTabs.count >= maxVisibleTabs {
                    Text("Maximum \(maxVisibleTabs) tabs. Drag to reorder.")
                } else {
                    Text("Drag to reorder. Tap to move to More.")
                }
            }

            // More section - shows hidden tabs
            Section {
                if moreTabs.isEmpty {
                    Text("No hidden tabs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(moreTabs, id: \.self) { tab in
                        tabRow(tab, inTabBar: false)
                    }
                    .onMove(perform: moveMoreTab)
                }
            } header: {
                HStack {
                    Text("More Menu")
                    Spacer()
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("These tabs are accessible from the More tab.")
            }

            Section {
                Button("Reset to Defaults") {
                    TabConfiguration.reset()
                    refreshTabs()
                    notifyChange()
                }
            }
        }
        .navigationTitle("Tab Bar")
        .environment(\.editMode, .constant(.active))
        .onAppear {
            refreshTabs()
        }
    }

    // MARK: Private

    @State private var tabBarTabs: [AppTab] = []
    @State private var moreTabs: [AppTab] = []

    /// Maximum tabs visible in tab bar (excluding More)
    private let maxVisibleTabs = 4

    private func tabRow(_ tab: AppTab, inTabBar: Bool) -> some View {
        let canMoveToTabBar = !inTabBar && tabBarTabs.count < maxVisibleTabs

        return Button {
            toggleTab(tab, inTabBar: inTabBar)
        } label: {
            HStack {
                Image(systemName: tab.icon)
                    .foregroundStyle(
                        inTabBar || canMoveToTabBar ? Color.accentColor : Color.secondary
                    )
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .foregroundStyle(inTabBar || canMoveToTabBar ? .primary : .secondary)
                    Text(tab.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Show action hint
                if inTabBar {
                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if canMoveToTabBar {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!inTabBar && !canMoveToTabBar)
    }

    private func refreshTabs() {
        let order = TabConfiguration.tabOrder()
        let hidden = TabConfiguration.hiddenTabs()

        tabBarTabs = order.filter { $0 != .more && !hidden.contains($0) }
        moreTabs = order.filter { $0 != .more && hidden.contains($0) }
    }

    private func toggleTab(_ tab: AppTab, inTabBar: Bool) {
        var hidden = TabConfiguration.hiddenTabs()

        if inTabBar {
            // Move from tab bar to more
            hidden.insert(tab)
        } else {
            // Move from more to tab bar (only if under limit)
            if tabBarTabs.count < maxVisibleTabs {
                hidden.remove(tab)
            }
        }

        TabConfiguration.saveHidden(hidden)
        refreshTabs()
        notifyChange()
    }

    private func moveTabBarTab(from source: IndexSet, to destination: Int) {
        tabBarTabs.move(fromOffsets: source, toOffset: destination)
        saveTabOrder()
    }

    private func moveMoreTab(from source: IndexSet, to destination: Int) {
        moreTabs.move(fromOffsets: source, toOffset: destination)
        saveTabOrder()
    }

    private func saveTabOrder() {
        // Combine tab bar tabs + more tabs + .more at end
        let newOrder = tabBarTabs + moreTabs + [.more]
        TabConfiguration.saveOrder(newOrder)
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .tabConfigurationChanged, object: nil)
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
