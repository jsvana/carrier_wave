import SwiftData
import SwiftUI

// MARK: - DashboardView Actions

extension DashboardView {
    func loadQRZConfig() {
        qrzIsConfigured = qrzClient.hasApiKey()
        qrzCallsign = qrzClient.getCallsign()
    }

    /// Refresh service configuration status from Keychain
    /// Called on appear to pick up changes made in settings
    func refreshServiceStatus() {
        lofiIsConfigured = lofiClient.isConfigured
        lofiIsLinked = lofiClient.isLinked
        lofiCallsign = lofiClient.getCallsign()
        hamrsIsConfigured = hamrsClient.isConfigured
        lotwIsConfigured = lotwClient.isConfigured
    }

    func performFullSync() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            let result = try await syncService.syncAll()
            print("Sync: down=\(result.downloaded), up=\(result.uploaded), new=\(result.newQSOs)")
            if !result.errors.isEmpty {
                print("Sync errors: \(result.errors)")
            }
            if result.potaMaintenanceSkipped {
                potaSyncResult = "Maintenance until 0400 UTC"
            }
        } catch {
            print("Sync error: \(error.localizedDescription)")
        }
    }

    func performDownloadOnly() async {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        do {
            let result = try await syncService.downloadOnly()
            let msg =
                "Download-only: down=\(result.downloaded), new=\(result.newQSOs), "
                    + "merged=\(result.mergedQSOs)"
            print(msg)
            if !result.errors.isEmpty {
                print("Download-only sync errors: \(result.errors)")
            }
        } catch {
            print("Download-only sync error: \(error.localizedDescription)")
        }
    }

    func syncFromLoFi() async {
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

    func performQRZSync() async {
        isSyncing = true
        syncingService = .qrz
        qrzSyncResult = "Syncing..."
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            let result = try await syncService.syncQRZ()
            if result.downloaded == 0, result.uploaded == 0, result.skipped == 0 {
                qrzSyncResult = "Already in sync"
            } else {
                var parts: [String] = []
                if result.downloaded > 0 {
                    parts.append("↓\(result.downloaded)")
                }
                if result.uploaded > 0 {
                    parts.append("↑\(result.uploaded)")
                }
                if result.skipped > 0 {
                    parts.append("⚠️\(result.skipped) skipped")
                }
                qrzSyncResult = parts.joined(separator: " ")
            }
        } catch {
            qrzSyncResult = "Error: \(error.localizedDescription)"
        }
    }

    func performPOTASync() async {
        isSyncing = true
        syncingService = .pota
        potaSyncResult = "Syncing..."
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            let result = try await syncService.syncPOTA()
            if result.downloaded == 0, result.uploaded == 0 {
                potaSyncResult = "Already in sync"
            } else {
                var parts: [String] = []
                if result.downloaded > 0 {
                    parts.append("↓\(result.downloaded)")
                }
                if result.uploaded > 0 {
                    parts.append("↑\(result.uploaded)")
                }
                potaSyncResult = parts.joined(separator: " ")
            }
        } catch POTAError.maintenanceWindow {
            potaSyncResult = "Maintenance until 0400 UTC"
        } catch {
            potaSyncResult = "Error: \(error.localizedDescription)"
        }
    }

    func clearQRZData() async {
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

    func clearLoFiData() async {
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
            lofiClient.resetSyncTimestamp()

            lofiSyncResult = "Cleared \(lofiQSOs.count) QSOs"
        } catch {
            lofiSyncResult = "Error: \(error.localizedDescription)"
        }
    }

    func syncFromHAMRS() async {
        isSyncing = true
        syncingService = .hamrs
        hamrsSyncResult = "Syncing..."
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            let count = try await syncService.syncHAMRS()
            hamrsSyncResult = count > 0 ? "+\(count) QSOs" : "Already in sync"
        } catch {
            hamrsSyncResult = "Error: \(error.localizedDescription)"
        }
    }

    func clearHAMRSCredentials() {
        hamrsClient.clearCredentials()
        hamrsSyncResult = nil
        refreshServiceStatus()
    }

    func syncFromLoTW() async {
        isSyncing = true
        syncingService = .lotw
        lotwSyncResult = "Syncing..."
        defer {
            isSyncing = false
            syncingService = nil
        }

        do {
            let count = try await syncService.syncLoTW()
            lotwSyncResult = count > 0 ? "+\(count) QSLs" : "Already in sync"
        } catch {
            lotwSyncResult = "Error: \(error.localizedDescription)"
        }
    }

    func clearLoTWData() {
        isSyncing = true
        lotwSyncResult = "Clearing..."
        defer { isSyncing = false }

        // Clear LoTW timestamps to allow re-download
        lotwClient.clearCredentials()
        lotwSyncResult = "Cleared"
        refreshServiceStatus()
    }

    // MARK: - Callsign Alias Detection

    /// Check for callsigns in QSOs that aren't configured as user callsigns
    func checkForUnconfiguredCallsigns() async {
        // Get all unique MYCALLSIGN values from QSOs
        let allMyCallsigns = Set(qsos.map { $0.myCallsign.uppercased() }.filter { !$0.isEmpty })

        // Skip check if no QSOs with callsigns
        guard !allMyCallsigns.isEmpty else {
            return
        }

        // Get unconfigured callsigns
        let unconfigured = await aliasService.getUnconfiguredCallsigns(from: allMyCallsigns)

        // Only show alert if there are unconfigured callsigns AND user has at least one configured
        let hasConfiguredCallsigns = await !aliasService.getAllUserCallsigns().isEmpty
        if !unconfigured.isEmpty, hasConfiguredCallsigns {
            unconfiguredCallsigns = unconfigured
            showingCallsignAliasAlert = true
        }
    }

    /// Add all unconfigured callsigns as previous callsigns
    func addUnconfiguredCallsignsAsAliases() async {
        for callsign in unconfiguredCallsigns {
            do {
                try await aliasService.addPreviousCallsign(callsign)
            } catch {
                print("Failed to add callsign alias \(callsign): \(error)")
            }
        }
        unconfiguredCallsigns = []
    }
}
