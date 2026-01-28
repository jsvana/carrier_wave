import Foundation
import SwiftData

// MARK: - SyncService Upload Methods

extension SyncService {
    func uploadToAllDestinations() async -> (
        results: [ServiceType: Result<Int, Error>], potaMaintenanceSkipped: Bool
    ) {
        let qsosNeedingUpload = try? fetchQSOsNeedingUpload()
        let timeout = syncTimeoutSeconds
        var potaMaintenanceSkipped = false

        let results = await withTaskGroup(of: (ServiceType, Result<Int, Error>).self) { group in
            // QRZ upload
            if qrzClient.hasApiKey() {
                let qrzQSOs = qsosNeedingUpload?.filter { $0.needsUpload(to: .qrz) } ?? []
                if !qrzQSOs.isEmpty {
                    group.addTask {
                        await self.uploadQRZBatch(qsos: qrzQSOs, timeout: timeout)
                    }
                }
            }

            // POTA upload (skip during maintenance window)
            if potaAuthService.isAuthenticated {
                if POTAClient.isInMaintenanceWindow() {
                    potaMaintenanceSkipped = true
                } else {
                    let potaQSOs =
                        qsosNeedingUpload?.filter {
                            $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
                        } ?? []
                    if !potaQSOs.isEmpty {
                        group.addTask {
                            await self.uploadPOTABatch(qsos: potaQSOs, timeout: timeout)
                        }
                    }
                }
            }

            var results: [ServiceType: Result<Int, Error>] = [:]
            for await (service, result) in group {
                results[service] = result
            }
            return results
        }

        return (results: results, potaMaintenanceSkipped: potaMaintenanceSkipped)
    }

    private func uploadQRZBatch(qsos: [QSO], timeout: TimeInterval) async -> (
        ServiceType, Result<Int, Error>
    ) {
        await MainActor.run { self.syncPhase = .uploading(service: .qrz) }
        do {
            let result = try await withTimeout(seconds: timeout, service: .qrz) {
                try await self.uploadToQRZ(qsos: qsos)
            }
            return (.qrz, .success(result.uploaded))
        } catch {
            return (.qrz, .failure(error))
        }
    }

    private func uploadPOTABatch(qsos: [QSO], timeout: TimeInterval) async -> (
        ServiceType, Result<Int, Error>
    ) {
        await MainActor.run { self.syncPhase = .uploading(service: .pota) }
        do {
            let count = try await withTimeout(seconds: timeout, service: .pota) {
                try await self.uploadToPOTA(qsos: qsos)
            }
            return (.pota, .success(count))
        } catch {
            return (.pota, .failure(error))
        }
    }

    func fetchQSOsNeedingUpload() throws -> [QSO] {
        let descriptor = FetchDescriptor<QSO>()
        let allQSOs = try modelContext.fetch(descriptor)
        return allQSOs.filter { qso in
            qso.servicePresence.contains { $0.needsUpload }
        }
    }

    func uploadToQRZ(qsos: [QSO]) async throws -> (uploaded: Int, skipped: Int) {
        let batchSize = 50
        var totalUploaded = 0
        var totalSkipped = 0

        for batch in stride(from: 0, to: qsos.count, by: batchSize) {
            let end = min(batch + batchSize, qsos.count)
            let batchQSOs = Array(qsos[batch ..< end])

            let uploadResult = try await qrzClient.uploadQSOs(batchQSOs)
            totalUploaded += uploadResult.uploaded
            totalSkipped += uploadResult.skipped

            // Only clear needsUpload for QSOs that were actually uploaded (matching callsign)
            // Non-matching QSOs keep their needsUpload flag - they're just skipped, not rejected
            let accountCallsign = qrzClient.getCallsign()?.uppercased()
            await MainActor.run {
                for qso in batchQSOs {
                    let qsoCallsign = qso.myCallsign.uppercased()
                    let matches = qsoCallsign.isEmpty || qsoCallsign == accountCallsign
                    if matches, let presence = qso.presence(for: .qrz) {
                        presence.needsUpload = false
                    }
                }
            }
        }

        // Warn user if QSOs were skipped due to callsign mismatch
        if totalSkipped > 0 {
            let callsign = qrzClient.getCallsign() ?? "unknown"
            SyncDebugLog.shared.warning(
                "Skipped \(totalSkipped) QSOs from other callsigns (QRZ account: \(callsign)). " +
                    "Go to Settings > Callsign Aliases to delete non-primary callsign QSOs.",
                service: .qrz
            )
        }

        return (uploaded: totalUploaded, skipped: totalSkipped)
    }

    func uploadToPOTA(qsos: [QSO]) async throws -> Int {
        // Filter out metadata pseudo-modes before grouping
        let realQsos = qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
        let byPark = POTAClient.groupQSOsByPark(realQsos)
        var totalUploaded = 0

        for (parkRef, parkQSOs) in byPark {
            let result = try await potaClient.uploadActivationWithRecording(
                parkReference: parkRef,
                qsos: parkQSOs,
                modelContext: modelContext
            )

            if result.success {
                totalUploaded += result.qsosAccepted

                // Mark as present in POTA
                await MainActor.run {
                    for qso in parkQSOs {
                        qso.markPresent(in: .pota, context: modelContext)
                    }
                }
            }
        }

        return totalUploaded
    }
}
