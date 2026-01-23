import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var qsos: [QSO]
    @Query private var allPresence: [ServicePresence]

    @ObservedObject var iCloudMonitor: ICloudMonitor
    @ObservedObject var potaAuth: POTAAuthService
    @ObservedObject var syncService: SyncService
    @Binding var selectedTab: AppTab

    @AppStorage("debugMode") private var debugMode = false

    private var importService: ImportService {
        ImportService(modelContext: modelContext)
    }

    private let lofiClient = LoFiClient()
    private let qrzClient = QRZClient()

    // Statistics
    private var stats: QSOStatistics {
        QSOStatistics(qsos: qsos)
    }

    // Derived counts from ServicePresence
    private func uploadedCount(for service: ServiceType) -> Int {
        let count = qsos.filter { qso in
            qso.servicePresence.contains { $0.serviceType == service && $0.isPresent }
        }.count
        // Debug: print breakdown
        if service == .lofi && debugMode {
            let total = qsos.count
            let withLofiPresence = qsos.filter { qso in
                qso.servicePresence.contains { $0.serviceType == .lofi }
            }.count
            let withLofiPresent = qsos.filter { qso in
                qso.servicePresence.contains { $0.serviceType == .lofi && $0.isPresent }
            }.count
            print("[Dashboard] LoFi count: total QSOs=\(total), with LoFi presence=\(withLofiPresence), with LoFi isPresent=true: \(withLofiPresent)")
        }
        return count
    }

    private func pendingCount(for service: ServiceType) -> Int {
        qsos.filter { qso in
            qso.servicePresence.contains { $0.serviceType == service && $0.needsUpload }
        }.count
    }

    @State private var isSyncing = false
    @State private var syncingService: ServiceType? = nil
    @State private var lastSyncDate: Date?
    @State private var lofiSyncResult: String?

    // QRZ state
    @State private var qrzCallsign: String?
    @State private var qrzIsConfigured: Bool = false
    @State private var showingQRZSetup: Bool = false
    @State private var qrzApiKey: String = ""
    @State private var qrzErrorMessage: String = ""
    @State private var showingQRZError: Bool = false
    @State private var qrzSyncResult: String?

    // POTA state
    @State private var showingPOTALogin: Bool = false
    @State private var potaSyncResult: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Activity Grid
                    activityCard

                    // Summary Stats
                    summaryCard

                    // Service Cards (2x2 grid)
                    HStack(spacing: 12) {
                        lofiCard
                        qrzCard
                    }
                    HStack(spacing: 12) {
                        potaCard
                        icloudCard
                    }
                }
                .padding()
            }
            .task {
                await loadQRZConfig()
            }
            .navigationTitle("Full Duplex")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        if debugMode {
                            Button {
                                Task { await performDownloadOnly() }
                            } label: {
                                if isSyncing {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                            }
                            .disabled(isSyncing)
                        }

                        Button {
                            Task { await performFullSync() }
                        } label: {
                            if isSyncing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                        .disabled(isSyncing)
                    }
                }
            }
        }
    }

    // MARK: - Activity Card (GitHub-style)

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()
                Text("\(stats.totalQSOs) QSOs")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ActivityGrid(activityData: stats.activityByDate)
                .frame(height: 115)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Statistics")
                    .font(.headline)
                Spacer()
                if let lastSync = lastSyncDate {
                    Text("Synced \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                Button {
                    selectedTab = .logs
                } label: {
                    StatBox(title: "QSOs", value: "\(stats.totalQSOs)", icon: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StatDetailView(category: .entities, items: stats.items(for: .entities))
                } label: {
                    StatBox(title: "DXCC Entities", value: "\(stats.uniqueEntities)", icon: "globe")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StatDetailView(category: .grids, items: stats.items(for: .grids))
                } label: {
                    StatBox(title: "Grids", value: "\(stats.uniqueGrids)", icon: "square.grid.3x3")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StatDetailView(category: .bands, items: stats.items(for: .bands))
                } label: {
                    StatBox(title: "Bands", value: "\(stats.uniqueBands)", icon: "waveform")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StatDetailView(category: .modes, items: stats.items(for: .modes))
                } label: {
                    StatBox(title: "Modes", value: "\(stats.uniqueModes)", icon: "dot.radiowaves.right")
                }
                .buttonStyle(.plain)

                NavigationLink {
                    StatDetailView(category: .parks, items: stats.items(for: .parks))
                } label: {
                    ActivationsStatBox(successful: stats.successfulActivations)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - LoFi Card

    private var lofiCard: some View {
        let synced = uploadedCount(for: .lofi)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Ham2K LoFi")
                    .font(.headline)
                Spacer()
                if lofiClient.isConfigured && lofiClient.isLinked {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let callsign = lofiClient.getCallsign() {
                        Text(callsign)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if lofiClient.isConfigured {
                    Image(systemName: "clock")
                        .foregroundStyle(.orange)
                    Text("Pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if lofiClient.isConfigured && lofiClient.isLinked {
                // Show sync status overlay during global sync
                if syncService.isSyncing {
                    SyncStatusOverlay(phase: syncService.syncPhase, service: .lofi)
                } else {
                    // Synced QSOs
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(synced) QSOs synced")
                            .font(.subheadline)
                    }

                    if let result = lofiSyncResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Debug mode: show individual sync button
                if debugMode && !syncService.isSyncing {
                    HStack {
                        AnimatedSyncButton(
                            title: "Sync",
                            isAnimating: syncingService == .lofi,
                            isDisabled: isSyncing
                        ) {
                            Task { await syncFromLoFi() }
                        }

                        Menu {
                            Button(role: .destructive) {
                                Task { await clearLoFiData() }
                            } label: {
                                Label("Clear LoFi Data", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isSyncing)
                    }
                }
            } else {
                NavigationLink {
                    LoFiSettingsView()
                } label: {
                    Label("Configure LoFi", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - QRZ Card

    private var qrzCard: some View {
        let inQRZ = uploadedCount(for: .qrz)
        let pending = pendingCount(for: .qrz)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QRZ Logbook")
                    .font(.headline)
                Spacer()
                if qrzIsConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let callsign = qrzCallsign {
                        Text(callsign)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if qrzIsConfigured {
                // Show sync status overlay during global sync
                if syncService.isSyncing {
                    SyncStatusOverlay(phase: syncService.syncPhase, service: .qrz)
                } else {
                    // Synced QSOs
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(inQRZ) QSOs synced")
                            .font(.subheadline)
                    }

                    // Pending upload
                    if pending > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundStyle(.orange)
                            Text("\(pending) pending sync")
                                .font(.subheadline)
                        }
                    }

                    if let result = qrzSyncResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Debug mode: show individual sync button
                if debugMode && !syncService.isSyncing {
                    HStack {
                        AnimatedSyncButton(
                            title: "Sync",
                            isAnimating: syncingService == .qrz,
                            isDisabled: isSyncing
                        ) {
                            Task { await performQRZSync() }
                        }

                        Menu {
                            Button(role: .destructive) {
                                Task { await clearQRZData() }
                            } label: {
                                Label("Clear QRZ Data", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isSyncing)
                    }
                }
            } else {
                Button {
                    showingQRZSetup = true
                } label: {
                    Label("Configure QRZ", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingQRZSetup) {
            QRZApiKeySheet(
                apiKey: $qrzApiKey,
                callsign: $qrzCallsign,
                isAuthenticated: $qrzIsConfigured,
                errorMessage: $qrzErrorMessage,
                showingError: $showingQRZError
            )
        }
        .alert("Error", isPresented: $showingQRZError) {
            Button("OK") { }
        } message: {
            Text(qrzErrorMessage)
        }
        .onChange(of: qrzIsConfigured) { _, isConfigured in
            if isConfigured {
                Task { await loadQRZConfig() }
            }
        }
    }

    // MARK: - POTA Card

    private var potaCard: some View {
        let inPOTA = uploadedCount(for: .pota)
        let pending = pendingCount(for: .pota)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("POTA")
                    .font(.headline)
                Spacer()
                if potaAuth.isAuthenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let callsign = potaAuth.currentToken?.callsign {
                        Text(callsign)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not logged in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if potaAuth.isAuthenticated {
                // Show sync status overlay during global sync
                if syncService.isSyncing {
                    SyncStatusOverlay(phase: syncService.syncPhase, service: .pota)
                } else {
                    // Synced QSOs
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(inPOTA) QSOs synced")
                            .font(.subheadline)
                    }

                    // Pending
                    if pending > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .foregroundStyle(.orange)
                            Text("\(pending) pending sync")
                                .font(.subheadline)
                        }
                    }

                    if let result = potaSyncResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Debug mode: show individual sync button
                if debugMode && !syncService.isSyncing {
                    HStack {
                        AnimatedSyncButton(
                            title: "Sync",
                            isAnimating: syncingService == .pota,
                            isDisabled: isSyncing
                        ) {
                            Task { await performPOTASync() }
                        }

                        Menu {
                            Button(role: .destructive) {
                                potaAuth.logout()
                            } label: {
                                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isSyncing)
                    }
                }
            } else {
                // Show stats even when not logged in
                if inPOTA > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(inPOTA) QSOs synced")
                            .font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingPOTALogin) {
            POTALoginSheet(authService: potaAuth)
        }
    }

    // MARK: - iCloud Card

    private var icloudCard: some View {
        let importedFromICloud = qsos.filter { $0.importSource == .icloud }.count
        let pendingCount = iCloudMonitor.pendingFiles.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("iCloud")
                    .font(.headline)
                Spacer()
                if iCloudMonitor.iCloudContainerURL != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Not available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if iCloudMonitor.iCloudContainerURL != nil {
                // Imported count
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.green)
                    Text("\(importedFromICloud) imported")
                        .font(.subheadline)
                }

                // Pending files
                if pendingCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .foregroundStyle(.orange)
                        Text("\(pendingCount) pending")
                            .font(.subheadline)
                    }
                }

                if iCloudMonitor.isMonitoring {
                    Text("Monitoring for files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func loadQRZConfig() async {
        qrzIsConfigured = await qrzClient.hasApiKey()
        qrzCallsign = await qrzClient.getCallsign()
    }

    private func performFullSync() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            let result = try await syncService.syncAll()
            print("Sync complete: downloaded \(result.downloaded), uploaded \(result.uploaded), new \(result.newQSOs), merged \(result.mergedQSOs)")
            if !result.errors.isEmpty {
                print("Sync errors: \(result.errors)")
            }
        } catch {
            print("Sync error: \(error.localizedDescription)")
        }
    }

    private func performDownloadOnly() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            let result = try await syncService.downloadOnly()
            print("Download-only sync complete: downloaded \(result.downloaded), new \(result.newQSOs), merged \(result.mergedQSOs)")
            if !result.errors.isEmpty {
                print("Download-only sync errors: \(result.errors)")
            }
        } catch {
            print("Download-only sync error: \(error.localizedDescription)")
        }
    }

    private func syncFromLoFi() async {
        isSyncing = true
        syncingService = .lofi
        lofiSyncResult = "Syncing..."
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            let count = try await syncService.syncLoFi()
            lofiSyncResult = count > 0 ? "+\(count) QSOs" : "Already in sync"
        } catch {
            lofiSyncResult = "Error: \(error.localizedDescription)"
        }
    }

    private func performQRZSync() async {
        isSyncing = true
        syncingService = .qrz
        qrzSyncResult = "Syncing..."
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            let result = try await syncService.syncQRZ()
            if result.downloaded == 0 && result.uploaded == 0 {
                qrzSyncResult = "Already in sync"
            } else {
                var parts: [String] = []
                if result.downloaded > 0 { parts.append("↓\(result.downloaded)") }
                if result.uploaded > 0 { parts.append("↑\(result.uploaded)") }
                qrzSyncResult = parts.joined(separator: " ")
            }
        } catch {
            qrzSyncResult = "Error: \(error.localizedDescription)"
        }
    }

    private func performPOTASync() async {
        isSyncing = true
        syncingService = .pota
        potaSyncResult = "Syncing..."
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            let result = try await syncService.syncPOTA()
            if result.downloaded == 0 && result.uploaded == 0 {
                potaSyncResult = "Already in sync"
            } else {
                var parts: [String] = []
                if result.downloaded > 0 { parts.append("↓\(result.downloaded)") }
                if result.uploaded > 0 { parts.append("↑\(result.uploaded)") }
                potaSyncResult = parts.joined(separator: " ")
            }
        } catch {
            potaSyncResult = "Error: \(error.localizedDescription)"
        }
    }

    private func clearQRZData() async {
        isSyncing = true
        qrzSyncResult = "Clearing..."
        defer { isSyncing = false }

        do {
            let descriptor = FetchDescriptor<QSO>()
            let allQSOs = try modelContext.fetch(descriptor)
            let qrzQSOs = allQSOs.filter { $0.importSource == .qrz }
            for qso in qrzQSOs {
                modelContext.delete(qso)
            }
            try modelContext.save()
            qrzSyncResult = "Cleared \(qrzQSOs.count) QSOs"
        } catch {
            qrzSyncResult = "Error: \(error.localizedDescription)"
        }
    }

    private func clearLoFiData() async {
        isSyncing = true
        lofiSyncResult = "Clearing..."
        defer { isSyncing = false }

        do {
            let descriptor = FetchDescriptor<QSO>()
            let allQSOs = try modelContext.fetch(descriptor)
            let lofiQSOs = allQSOs.filter { $0.importSource == .lofi }
            for qso in lofiQSOs {
                modelContext.delete(qso)
            }
            try modelContext.save()

            // Reset sync timestamp so QSOs can be re-downloaded
            await lofiClient.resetSyncTimestamp()

            lofiSyncResult = "Cleared \(lofiQSOs.count) QSOs"
        } catch {
            lofiSyncResult = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Statistics

struct QSOStatistics {
    let qsos: [QSO]

    var totalQSOs: Int { qsos.count }

    var uniqueEntities: Int {
        Set(qsos.compactMap { $0.dxccEntity?.number }).count
    }

    var uniqueGrids: Int {
        Set(qsos.compactMap(\.theirGrid).filter { !$0.isEmpty }).count
    }

    var uniqueBands: Int {
        Set(qsos.map(\.band)).count
    }

    var uniqueModes: Int {
        Set(qsos.map(\.mode)).count
    }

    var uniqueParks: Int {
        Set(qsos.compactMap(\.parkReference).filter { !$0.isEmpty }).count
    }

    /// Activations with 10+ QSOs (valid POTA activations)
    /// Each activation is a unique park+date combination
    var successfulActivations: Int {
        let parksOnly = qsos.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        // Group by park + date (each day at a park is a separate activation)
        let grouped = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.dateOnly.timeIntervalSince1970)"
        }
        return grouped.values.filter { $0.count >= 10 }.count
    }

    /// Activations with <10 QSOs (activation attempts)
    /// Each activation is a unique park+date combination
    var attemptedActivations: Int {
        let parksOnly = qsos.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        // Group by park + date (each day at a park is a separate activation)
        let grouped = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.dateOnly.timeIntervalSince1970)"
        }
        return grouped.values.filter { $0.count < 10 }.count
    }

    var activityByDate: [Date: Int] {
        var activity: [Date: Int] = [:]
        for qso in qsos {
            let date = qso.dateOnly
            activity[date, default: 0] += 1
        }
        return activity
    }

    func items(for category: StatCategoryType) -> [StatCategoryItem] {
        switch category {
        case .entities:
            return groupedByEntity()
        case .grids:
            return groupedByGrid()
        case .bands:
            return groupedByBand()
        case .modes:
            return groupedByMode()
        case .parks:
            return groupedByPark()
        }
    }

    private func groupedByEntity() -> [StatCategoryItem] {
        // Group by DXCC entity number
        let withEntity = qsos.filter { $0.dxccEntity != nil }
        let grouped = Dictionary(grouping: withEntity) { $0.dxccEntity!.number }
        return grouped.map { entityNumber, qsos in
            let entity = qsos.first?.dxccEntity
            return StatCategoryItem(
                identifier: entity?.name ?? "Unknown",
                description: "DXCC #\(entityNumber)",
                qsos: qsos
            )
        }
    }

    private func groupedByGrid() -> [StatCategoryItem] {
        let gridsOnly = qsos.filter { $0.theirGrid != nil && !$0.theirGrid!.isEmpty }
        let grouped = Dictionary(grouping: gridsOnly) { $0.theirGrid! }
        return grouped.map { grid, qsos in
            StatCategoryItem(
                identifier: grid,
                description: DescriptionLookup.gridDescription(for: grid),
                qsos: qsos
            )
        }
    }

    private func groupedByBand() -> [StatCategoryItem] {
        let grouped = Dictionary(grouping: qsos) { $0.band }
        return grouped.map { band, qsos in
            StatCategoryItem(
                identifier: band,
                description: DescriptionLookup.bandDescription(for: band),
                qsos: qsos
            )
        }
    }

    private func groupedByMode() -> [StatCategoryItem] {
        let grouped = Dictionary(grouping: qsos) { $0.mode }
        return grouped.map { mode, qsos in
            StatCategoryItem(
                identifier: mode,
                description: DescriptionLookup.modeDescription(for: mode),
                qsos: qsos
            )
        }
    }

    private func groupedByPark() -> [StatCategoryItem] {
        let parksOnly = qsos.filter { $0.parkReference != nil && !$0.parkReference!.isEmpty }
        // Group by park + date (each day at a park is a separate activation)
        let grouped = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.dateOnly.timeIntervalSince1970)"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return grouped.map { key, qsos in
            let park = qsos.first?.parkReference ?? "Unknown"
            let date = qsos.first?.dateOnly ?? Date()
            let status = qsos.count >= 10 ? "✓" : "(\(qsos.count)/10)"
            return StatCategoryItem(
                identifier: "\(park) - \(dateFormatter.string(from: date))",
                description: status,
                qsos: qsos
            )
        }
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Activations Stat Box

struct ActivationsStatBox: View {
    let successful: Int

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "leaf")
                .font(.title3)
                .foregroundStyle(.blue)
            Text("\(successful)")
                .font(.title2)
                .fontWeight(.bold)
            Text("Activations")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Activity Grid (GitHub-style)

struct ActivityGrid: View {
    let activityData: [Date: Int]

    @State private var selectedDate: Date?

    private let columns = 26
    private let rows = 7

    private var maxCount: Int {
        activityData.values.max() ?? 1
    }

    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private let tooltipDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private func dateFor(column: Int, row: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        let weeksBack = columns - 1 - column
        let daysBack = weeksBack * 7 + (todayWeekday - 1 - row)
        return calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
    }

    private func colorFor(count: Int) -> Color {
        if count == 0 {
            return Color(.systemGray5)
        }
        let intensity = min(Double(count) / Double(max(maxCount, 1)), 1.0)
        return Color.green.opacity(0.3 + intensity * 0.7)
    }

    private var monthLabelPositions: [(column: Int, label: String)] {
        var labels: [(Int, String)] = []
        var lastMonth = -1

        for column in 0..<columns {
            let date = dateFor(column: column, row: 0)
            let month = calendar.component(.month, from: date)

            if month != lastMonth {
                labels.append((column, monthFormatter.string(from: date)))
                lastMonth = month
            }
        }
        return labels
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let gridWidth = geometry.size.width
            let cellSize = (gridWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let gridHeight = CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
            let columnWidth = cellSize + spacing

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        VStack(spacing: spacing) {
                            ForEach(0..<rows, id: \.self) { row in
                                let date = dateFor(column: column, row: row)
                                let count = activityData[date] ?? 0

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorFor(count: count))
                                    .frame(width: cellSize, height: cellSize)
                                    .onTapGesture {
                                        if selectedDate == date {
                                            selectedDate = nil
                                        } else {
                                            selectedDate = date
                                        }
                                    }
                                    .popover(isPresented: Binding(
                                        get: { selectedDate == date },
                                        set: { if !$0 { selectedDate = nil } }
                                    ), arrowEdge: .top) {
                                        VStack(spacing: 4) {
                                            Text(tooltipDateFormatter.string(from: date))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(count) QSO\(count == 1 ? "" : "s")")
                                                .font(.headline)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .presentationCompactAdaptation(.popover)
                                    }
                            }
                        }
                    }
                }
                .frame(height: gridHeight)

                ZStack(alignment: .topLeading) {
                    ForEach(monthLabelPositions, id: \.column) { item in
                        Text(item.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: CGFloat(item.column) * columnWidth)
                    }
                }
                .frame(width: gridWidth, height: 14, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Animated Sync Button

struct AnimatedSyncButton: View {
    let title: String
    let isAnimating: Bool
    let isDisabled: Bool
    let action: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .rotationEffect(.degrees(rotation))
                Text(title)
            }
        }
        .buttonStyle(.bordered)
        .disabled(isDisabled)
        .onChange(of: isAnimating) { _, animating in
            if animating {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            } else {
                withAnimation(.default) {
                    rotation = 0
                }
            }
        }
    }
}

// MARK: - Sync Status Overlay

struct SyncStatusOverlay: View {
    let phase: SyncService.SyncPhase?
    let service: ServiceType

    @State private var pulseScale: CGFloat = 1.0
    @State private var rotation: Double = 0

    private var isActive: Bool {
        guard let phase = phase else { return false }
        switch phase {
        case .downloading(let s), .uploading(let s):
            return s == service
        case .processing:
            return true
        }
    }

    private var statusText: String {
        guard let phase = phase else { return "" }
        switch phase {
        case .downloading(let s) where s == service:
            return "Downloading..."
        case .uploading(let s) where s == service:
            return "Uploading..."
        case .processing:
            return "Processing..."
        default:
            return "Waiting..."
        }
    }

    private var statusColor: Color {
        guard let phase = phase else { return .gray }
        switch phase {
        case .downloading(let s) where s == service:
            return .blue
        case .uploading(let s) where s == service:
            return .green
        case .processing:
            return .orange
        default:
            return .gray
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            // Animated spinner
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.subheadline)
                .foregroundStyle(statusColor)
                .rotationEffect(.degrees(rotation))
                .scaleEffect(pulseScale)

            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulseScale = 1.1
            }
        }
    }
}
