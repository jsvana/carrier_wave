import Combine
import Foundation
import SwiftData

@MainActor
class SyncService: ObservableObject {
    private let modelContext: ModelContext
    private let qrzClient: QRZClient
    private let potaClient: POTAClient

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncProgress: SyncProgress?

    struct SyncProgress {
        var destination: DestinationType
        var current: Int
        var total: Int
    }

    struct SyncResult {
        var qrzUploaded: Int
        var qrzDuplicates: Int
        var qrzErrors: [String]
        var potaUploaded: Int
        var potaErrors: [String]
    }

    init(modelContext: ModelContext, potaAuthService: POTAAuthService) {
        self.modelContext = modelContext
        self.qrzClient = QRZClient()
        self.potaClient = POTAClient(authService: potaAuthService)
    }

    func syncAll() async throws -> SyncResult {
        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        var result = SyncResult(
            qrzUploaded: 0,
            qrzDuplicates: 0,
            qrzErrors: [],
            potaUploaded: 0,
            potaErrors: []
        )

        // Sync to QRZ
        do {
            let qrzResult = try await syncToQRZ()
            result.qrzUploaded = qrzResult.uploaded
            result.qrzDuplicates = qrzResult.duplicates
        } catch {
            result.qrzErrors.append(error.localizedDescription)
        }

        // Sync to POTA
        do {
            let potaResult = try await syncToPOTA()
            result.potaUploaded = potaResult
        } catch {
            result.potaErrors.append(error.localizedDescription)
        }

        return result
    }

    func syncToQRZ() async throws -> (uploaded: Int, duplicates: Int) {
        syncProgress = SyncProgress(destination: .qrz, current: 0, total: 0)

        let pendingRecords = try fetchPendingSyncRecords(for: .qrz)
        guard !pendingRecords.isEmpty else {
            return (uploaded: 0, duplicates: 0)
        }

        let qsos = pendingRecords.compactMap(\.qso)
        syncProgress?.total = qsos.count

        let batchSize = 50
        var totalUploaded = 0
        var totalDuplicates = 0

        for batch in stride(from: 0, to: qsos.count, by: batchSize) {
            let end = min(batch + batchSize, qsos.count)
            let batchQSOs = Array(qsos[batch..<end])

            let result = try await qrzClient.uploadQSOs(batchQSOs)
            totalUploaded += result.uploaded
            totalDuplicates += result.duplicates

            for qso in batchQSOs {
                if let record = qso.syncRecords.first(where: { $0.destinationType == .qrz }) {
                    record.status = .uploaded
                    record.uploadedAt = Date()
                }
            }

            try modelContext.save()
            syncProgress?.current = end
        }

        return (uploaded: totalUploaded, duplicates: totalDuplicates)
    }

    func syncToPOTA() async throws -> Int {
        syncProgress = SyncProgress(destination: .pota, current: 0, total: 0)

        let pendingRecords = try fetchPendingSyncRecords(for: .pota)
        let qsos = pendingRecords.compactMap(\.qso)

        let byPark = POTAClient.groupQSOsByPark(qsos)
        syncProgress?.total = byPark.count

        var totalUploaded = 0
        var currentPark = 0

        for (parkRef, parkQSOs) in byPark {
            let result = try await potaClient.uploadActivation(
                parkReference: parkRef,
                qsos: parkQSOs
            )

            if result.success {
                totalUploaded += result.qsosAccepted

                for qso in parkQSOs {
                    if let record = qso.syncRecords.first(where: { $0.destinationType == .pota }) {
                        record.status = .uploaded
                        record.uploadedAt = Date()
                    }
                }
            }

            currentPark += 1
            syncProgress?.current = currentPark
            try modelContext.save()
        }

        return totalUploaded
    }

    private func fetchPendingSyncRecords(for destination: DestinationType) throws -> [SyncRecord] {
        let descriptor = FetchDescriptor<SyncRecord>()
        let allRecords = try modelContext.fetch(descriptor)
        return allRecords.filter { $0.destinationType == destination && $0.status == .pending }
    }
}
