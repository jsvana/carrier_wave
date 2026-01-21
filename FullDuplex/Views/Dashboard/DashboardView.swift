import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var qsos: [QSO]
    @Query private var allSyncRecords: [SyncRecord]

    @ObservedObject var iCloudMonitor: ICloudMonitor
    @StateObject private var potaAuth = POTAAuthService()

    // Computed property for sync service (needs modelContext)
    private var syncService: SyncService {
        SyncService(modelContext: modelContext, potaAuthService: potaAuth)
    }

    private var pendingSyncs: [SyncRecord] {
        allSyncRecords.filter { $0.status == .pending }
    }

    @State private var isSyncing = false
    @State private var lastSyncDate: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard

                    HStack(spacing: 12) {
                        destinationCard(for: .qrz)
                        destinationCard(for: .pota)
                    }

                    recentImportsCard

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

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Summary")
                .font(.headline)

            HStack {
                Label("\(qsos.count) QSOs", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                if let lastSync = lastSyncDate {
                    Text("Last sync: \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func destinationCard(for type: DestinationType) -> some View {
        let totalForDest = qsos.count
        let pending = pendingSyncs.filter { $0.destinationType == type }.count
        let synced = totalForDest - pending

        return VStack(alignment: .leading, spacing: 8) {
            Text(type.displayName)
                .font(.headline)

            if pending > 0 {
                Label("\(synced)/\(totalForDest)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("\(pending) pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("\(synced)/\(totalForDest)", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Text("Synced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var recentImportsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Imports")
                .font(.headline)

            let recentQSOs = Array(qsos.sorted { $0.importedAt > $1.importedAt }.prefix(5))

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
                            .foregroundStyle(.secondary)
                        Text(qso.importedAt, style: .relative)
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

    private func performSync() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            let result = try await syncService.syncAll()
            print("Sync complete: QRZ uploaded \(result.qrzUploaded), POTA uploaded \(result.potaUploaded)")
        } catch {
            print("Sync error: \(error.localizedDescription)")
        }
    }
}
