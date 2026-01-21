import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var qsos: [QSO]
    @Query private var allSyncRecords: [SyncRecord]

    @ObservedObject var iCloudMonitor: ICloudMonitor
    @StateObject private var potaAuth = POTAAuthService()

    private var syncService: SyncService {
        SyncService(modelContext: modelContext, potaAuthService: potaAuth)
    }

    private var importService: ImportService {
        ImportService(modelContext: modelContext)
    }

    private let lofiClient = LoFiClient()

    private var pendingSyncs: [SyncRecord] {
        allSyncRecords.filter { $0.status == .pending }
    }

    // Statistics
    private var stats: QSOStatistics {
        QSOStatistics(qsos: qsos)
    }

    @State private var isSyncing = false
    @State private var lastSyncDate: Date?
    @State private var lofiImportResult: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Activity Grid
                    activityCard

                    // Summary Stats
                    summaryCard

                    // LoFi Card (always show if configured)
                    lofiCard

                    // Destination Cards
                    HStack(spacing: 12) {
                        destinationCard(for: .qrz)
                        destinationCard(for: .pota)
                    }

                    // Recent Imports
                    recentImportsCard

                    // Pending iCloud Files
                    if !iCloudMonitor.pendingFiles.isEmpty {
                        pendingFilesCard
                    }
                }
                .padding()
            }
            .navigationTitle("Full Duplex")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await performSync() }
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
                .frame(height: 115) // Extra height for month labels
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
                StatBox(title: "QSOs", value: "\(stats.totalQSOs)", icon: "antenna.radiowaves.left.and.right")
                StatBox(title: "Entities", value: "\(stats.uniqueEntities)", icon: "globe")
                StatBox(title: "Grids", value: "\(stats.uniqueGrids)", icon: "square.grid.3x3")
                StatBox(title: "Bands", value: "\(stats.uniqueBands)", icon: "waveform")
                StatBox(title: "Modes", value: "\(stats.uniqueModes)", icon: "dot.radiowaves.right")
                StatBox(title: "Parks", value: "\(stats.uniqueParks)", icon: "leaf")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - LoFi Card

    private var lofiCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Ham2K LoFi", systemImage: "antenna.radiowaves.left.and.right")
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

            // Show LoFi-imported QSO count
            let lofiQSOs = qsos.filter { $0.importSource == .lofi }
            if !lofiQSOs.isEmpty {
                Text("\(lofiQSOs.count) QSOs from LoFi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let result = lofiImportResult {
                Text(result)
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            if lofiClient.isConfigured && lofiClient.isLinked {
                Button {
                    Task { await syncFromLoFi() }
                } label: {
                    Label("Sync from LoFi", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .disabled(isSyncing)
            } else {
                NavigationLink {
                    LoFiSettingsView()
                } label: {
                    Label("Configure LoFi", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Destination Card

    private func destinationCard(for type: DestinationType) -> some View {
        let totalForDest = qsos.count
        let pending = pendingSyncs.filter { $0.destinationType == type }.count
        let synced = totalForDest - pending

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(type.displayName)
                    .font(.headline)
                Spacer()
                if pending > 0 {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if synced > 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Text("\(synced)/\(totalForDest) synced")
                .font(.subheadline)

            if pending > 0 {
                Text("\(pending) pending")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Type-specific stats
            if type == .pota {
                let parksCount = stats.uniqueParks
                if parksCount > 0 {
                    Text("\(parksCount) parks")
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

    // MARK: - Recent Imports Card

    private var recentImportsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent QSOs")
                .font(.headline)

            let recentQSOs = Array(qsos.sorted { $0.timestamp > $1.timestamp }.prefix(5))

            if recentQSOs.isEmpty {
                Text("No logs imported yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(recentQSOs) { qso in
                    HStack {
                        Text(qso.callsign)
                            .fontWeight(.medium)
                        Spacer()
                        Text(qso.band)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .clipShape(Capsule())
                        Text(qso.mode)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(qso.timestamp, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Pending Files Card

    private var pendingFilesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(iCloudMonitor.pendingFiles.count) new file(s) in iCloud",
                  systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(iCloudMonitor.pendingFiles, id: \.self) { url in
                HStack {
                    Text(url.lastPathComponent)
                    Spacer()
                    Button("Import") {
                        // TODO: Trigger import
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func performSync() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        if lofiClient.isConfigured && lofiClient.isLinked {
            await syncFromLoFi()
        }

        do {
            let result = try await syncService.syncAll()
            print("Sync complete: QRZ uploaded \(result.qrzUploaded), POTA uploaded \(result.potaUploaded)")
        } catch {
            print("Sync error: \(error.localizedDescription)")
        }
    }

    private func syncFromLoFi() async {
        do {
            let qsos = try await lofiClient.fetchAllQsosSinceLastSync()
            if qsos.isEmpty {
                lofiImportResult = "No new QSOs"
                return
            }

            let result = try await importService.importFromLoFi(qsos: qsos)
            lofiImportResult = "+\(result.imported) QSOs"
        } catch {
            lofiImportResult = "Error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Statistics

struct QSOStatistics {
    let qsos: [QSO]

    var totalQSOs: Int { qsos.count }

    var uniqueEntities: Int {
        Set(qsos.map(\.callsignPrefix)).count
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
        let grouped = Dictionary(grouping: qsos) { $0.callsignPrefix }
        return grouped.map { prefix, qsos in
            StatCategoryItem(
                identifier: prefix,
                description: DescriptionLookup.entityDescription(for: prefix),
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
        let grouped = Dictionary(grouping: parksOnly) { $0.parkReference! }
        return grouped.map { park, qsos in
            StatCategoryItem(
                identifier: park,
                description: DescriptionLookup.parkDescription(for: park),
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

// MARK: - Activity Grid (GitHub-style)

struct ActivityGrid: View {
    let activityData: [Date: Int]

    private let columns = 26 // ~6 months of weeks
    private let rows = 7 // days of week

    private var maxCount: Int {
        activityData.values.max() ?? 1
    }

    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()

    private func dateFor(column: Int, row: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)

        // Calculate offset: column 0 is oldest, last column is current week
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

    /// Get month label positions
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
                // Grid cells
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        VStack(spacing: spacing) {
                            ForEach(0..<rows, id: \.self) { row in
                                let date = dateFor(column: column, row: row)
                                let count = activityData[date] ?? 0

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorFor(count: count))
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
                .frame(height: gridHeight)

                // Month labels - positioned absolutely
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

