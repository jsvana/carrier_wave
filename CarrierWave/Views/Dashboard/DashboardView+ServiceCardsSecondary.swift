import SwiftData
import SwiftUI

// MARK: - DashboardView Secondary Service Cards (HAMRS, LoTW, iCloud)

extension DashboardView {
    // MARK: - HAMRS Card

    var hamrsCard: some View {
        let synced = uploadedCount(for: .hamrs)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HAMRS")
                    .font(.headline)
                Spacer()
                if hamrsIsConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Connected")
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if hamrsIsConfigured {
                // Show sync status overlay during global sync
                if syncService.isSyncing {
                    SyncStatusOverlay(phase: syncService.syncPhase, service: .hamrs)
                } else {
                    // Synced QSOs
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(synced) QSOs synced")
                            .font(.subheadline)
                    }

                    if let result = hamrsSyncResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Debug mode: show individual sync button
                if debugMode, !syncService.isSyncing {
                    AnimatedSyncButton(
                        title: "Sync",
                        isAnimating: syncingService == .hamrs,
                        isDisabled: isSyncing
                    ) {
                        Task { await syncFromHAMRS() }
                    }
                }
            } else {
                NavigationLink {
                    HAMRSSettingsView()
                } label: {
                    Label("Configure", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - LoTW Card

    var lotwCard: some View {
        // LoTW tracks QSOs uploaded and QSLs confirmed
        let synced = uploadedCount(for: .lotw)
        let confirmed = qsos.filter(\.lotwConfirmed).count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LoTW")
                    .font(.headline)
                Spacer()
                if lotwIsConfigured {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Connected")
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if lotwIsConfigured {
                // Show sync status overlay during global sync
                if syncService.isSyncing {
                    SyncStatusOverlay(phase: syncService.syncPhase, service: .lotw)
                } else {
                    // QSOs synced to LoTW
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(.blue)
                        Text("\(synced) QSOs synced")
                            .font(.subheadline)
                    }

                    // QSL confirmations from LoTW
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal")
                            .foregroundStyle(.green)
                        Text("\(confirmed) QSLs confirmed")
                            .font(.subheadline)
                    }

                    if let result = lotwSyncResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                // Debug mode: show individual sync button
                if debugMode, !syncService.isSyncing {
                    HStack {
                        AnimatedSyncButton(
                            title: "Sync",
                            isAnimating: syncingService == .lotw,
                            isDisabled: isSyncing
                        ) {
                            Task { await syncFromLoTW() }
                        }

                        Menu {
                            Button(role: .destructive) {
                                Task { await clearLoTWData() }
                            } label: {
                                Label("Clear LoTW Data", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .disabled(isSyncing)
                    }
                }
            } else {
                NavigationLink {
                    LoTWSettingsView()
                } label: {
                    Label("Configure", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - iCloud Card

    var icloudCard: some View {
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
                        .accessibilityLabel("Available")
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
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
