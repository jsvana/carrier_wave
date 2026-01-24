import Foundation
import SwiftData

// MARK: - SyncService Upload Methods

extension SyncService {
    func uploadToAllDestinations() async -> [ServiceType: Result<Int, Error>] {
        let qsosNeedingUpload = try? fetchQSOsNeedingUpload()
        let timeout = syncTimeoutSeconds

        return await withTaskGroup(of: (ServiceType, Result<Int, Error>).self) { group in
            // QRZ upload
            if await qrzClient.hasApiKey() {
                let qrzQSOs = qsosNeedingUpload?.filter { $0.needsUpload(to: .qrz) } ?? []
                if !qrzQSOs.isEmpty {
                    group.addTask {
                        await self.uploadQRZBatch(qsos: qrzQSOs, timeout: timeout)
                    }
                }
            }

            // POTA upload
            if potaAuthService.isAuthenticated {
                let potaQSOs = qsosNeedingUpload?.filter {
                    $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
                } ?? []
                if !potaQSOs.isEmpty {
                    group.addTask {
                        await self.uploadPOTABatch(qsos: potaQSOs, timeout: timeout)
                    }
                }
            }

            var results: [ServiceType: Result<Int, Error>] = [:]
            for await (service, result) in group {
                results[service] = result
            }
            return results
        }
    }

    private func uploadQRZBatch(qsos: [QSO], timeout: TimeInterval) async -> (ServiceType, Result<Int, Error>) {
        await MainActor.run { self.syncPhase = .uploading(service: .qrz) }
        do {
            let count = try await withTimeout(seconds: timeout, service: .qrz) {
                try await self.uploadToQRZ(qsos: qsos)
            }
            return (.qrz, .success(count))
        } catch {
            return (.qrz, .failure(error))
        }
    }

    private func uploadPOTABatch(qsos: [QSO], timeout: TimeInterval) async -> (ServiceType, Result<Int, Error>) {
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

    func uploadToQRZ(qsos: [QSO]) async throws -> Int {
        let batchSize = 50
        var totalUploaded = 0

        for batch in stride(from: 0, to: qsos.count, by: batchSize) {
            let end = min(batch + batchSize, qsos.count)
            let batchQSOs = Array(qsos[batch ..< end])

            let result = try await qrzClient.uploadQSOs(batchQSOs)
            totalUploaded += result.uploaded

            // Clear needsUpload flag - don't mark as present yet.
            // Let the next download confirm actual presence in QRZ.
            await MainActor.run {
                for qso in batchQSOs {
                    if let presence = qso.presence(for: .qrz) {
                        presence.needsUpload = false
                    }
                }
            }
        }

        return totalUploaded
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
