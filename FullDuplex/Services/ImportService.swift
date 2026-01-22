import Combine
import Foundation
import SwiftData

@MainActor
class ImportService: ObservableObject {
    private let modelContext: ModelContext
    private let parser = ADIFParser()

    @Published var isImporting = false
    @Published var lastImportResult: ImportResult?

    struct ImportResult {
        let totalRecords: Int
        let imported: Int
        let duplicates: Int
        let errors: Int
        let matched: Int
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func importADIF(from url: URL, source: ImportSource, myCallsign: String) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw ImportError.invalidFile
        }

        return try await importADIF(content: content, source: source, myCallsign: myCallsign)
    }

    func importADIF(content: String, source: ImportSource, myCallsign: String) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        let records = try parser.parse(content)

        var imported = 0
        var duplicates = 0
        var errors = 0

        let existingKeys = try fetchExistingDeduplicationKeys()

        for record in records {
            do {
                let qso = try createQSO(from: record, source: source, myCallsign: myCallsign)

                if existingKeys.contains(qso.deduplicationKey) {
                    duplicates += 1
                    continue
                }

                modelContext.insert(qso)

                // Create service presence records
                createServicePresenceRecords(for: qso, importedFrom: nil)

                imported += 1
            } catch {
                errors += 1
            }
        }

        try modelContext.save()

        let result = ImportResult(
            totalRecords: records.count,
            imported: imported,
            duplicates: duplicates,
            errors: errors,
            matched: 0
        )

        lastImportResult = result
        return result
    }

    private func fetchExistingDeduplicationKeys() throws -> Set<String> {
        let descriptor = FetchDescriptor<QSO>()
        let qsos = try modelContext.fetch(descriptor)
        return Set(qsos.map(\.deduplicationKey))
    }

    private func createQSO(from record: ADIFRecord, source: ImportSource, myCallsign: String) throws -> QSO {
        guard let timestamp = record.timestamp else {
            throw ImportError.missingTimestamp
        }

        return QSO(
            callsign: record.callsign,
            band: record.band,
            mode: record.mode,
            frequency: record.frequency,
            timestamp: timestamp,
            rstSent: record.rstSent,
            rstReceived: record.rstReceived,
            myCallsign: record.myCallsign ?? myCallsign,
            myGrid: record.myGridsquare,
            theirGrid: record.gridsquare,
            parkReference: record.sigInfo,
            notes: record.comment,
            importSource: source,
            rawADIF: record.rawADIF
        )
    }

    /// Create ServicePresence records for a new QSO
    /// - Parameters:
    ///   - qso: The QSO to create presence records for
    ///   - importedFrom: The service the QSO was imported from (if any)
    private func createServicePresenceRecords(for qso: QSO, importedFrom: ServiceType?) {
        for service in ServiceType.allCases {
            if service == importedFrom {
                // This QSO came from this service, mark as present
                let presence = ServicePresence.downloaded(from: service, qso: qso)
                modelContext.insert(presence)
                qso.servicePresence.append(presence)
            } else if service.supportsUpload {
                // Needs to be uploaded to this service
                let presence = ServicePresence.needsUpload(to: service, qso: qso)
                modelContext.insert(presence)
                qso.servicePresence.append(presence)
            }
            // LoFi is download-only, so if it wasn't the source, don't create a presence record
        }
    }

    // MARK: - LoFi Import

    func importFromLoFi(qsos: [(LoFiQso, LoFiOperation)]) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        var imported = 0
        var duplicates = 0
        var errors = 0

        let existingKeys = try fetchExistingDeduplicationKeys()

        for (lofiQso, operation) in qsos {
            do {
                let qso = try createQSO(from: lofiQso, operation: operation)

                if existingKeys.contains(qso.deduplicationKey) {
                    duplicates += 1
                    continue
                }

                modelContext.insert(qso)

                // Mark as present in LoFi, needs upload to others
                createServicePresenceRecords(for: qso, importedFrom: .lofi)

                imported += 1
            } catch {
                errors += 1
            }
        }

        try modelContext.save()

        let result = ImportResult(
            totalRecords: qsos.count,
            imported: imported,
            duplicates: duplicates,
            errors: errors,
            matched: 0
        )

        lastImportResult = result
        return result
    }

    private func createQSO(from lofiQso: LoFiQso, operation: LoFiOperation) throws -> QSO {
        guard let callsign = lofiQso.theirCall else {
            throw ImportError.parseError("Missing their callsign")
        }

        guard let band = lofiQso.band else {
            throw ImportError.parseError("Missing band")
        }

        guard let mode = lofiQso.mode else {
            throw ImportError.parseError("Missing mode")
        }

        let myCallsign = lofiQso.ourCall ?? operation.stationCall

        // Get park reference from operation refs
        let parkRef = lofiQso.myPotaRef(from: operation.refs)

        return QSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: lofiQso.freqMHz,
            timestamp: lofiQso.timestamp,
            rstSent: lofiQso.rstSent,
            rstReceived: lofiQso.rstRcvd,
            myCallsign: myCallsign,
            myGrid: operation.grid,
            theirGrid: lofiQso.theirGrid,
            parkReference: parkRef,
            notes: lofiQso.notes,
            importSource: .lofi
        )
    }

    // MARK: - QRZ Import (with merge)

    func importFromQRZ(qsos: [QRZFetchedQSO], myCallsign: String) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        var imported = 0
        var updated = 0

        // Fetch existing QSOs for matching
        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)

        // Build lookup maps
        let byQrzLogId = Dictionary(grouping: existingQSOs.filter { $0.qrzLogId != nil }) { $0.qrzLogId! }
        let byDedupeKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }

        for qrzQso in qsos {
            // Try to find existing by QRZ log ID first
            if let qrzLogId = qrzQso.qrzLogId, let existing = byQrzLogId[qrzLogId]?.first {
                // Update confirmation status
                existing.qrzConfirmed = qrzQso.qrzConfirmed
                existing.lotwConfirmedDate = qrzQso.lotwConfirmedDate
                // Mark QRZ as present (it's already in QRZ)
                existing.markPresent(in: .qrz, context: modelContext)
                updated += 1
                continue
            }

            // Try to find by deduplication key
            let tempQso = QSO(
                callsign: qrzQso.callsign,
                band: qrzQso.band,
                mode: qrzQso.mode,
                timestamp: qrzQso.timestamp,
                myCallsign: qrzQso.myCallsign ?? myCallsign,
                importSource: .qrz
            )
            let dedupeKey = tempQso.deduplicationKey

            if let existing = byDedupeKey[dedupeKey]?.first {
                // Update with QRZ data
                existing.qrzLogId = qrzQso.qrzLogId
                existing.qrzConfirmed = qrzQso.qrzConfirmed
                existing.lotwConfirmedDate = qrzQso.lotwConfirmedDate
                // Mark QRZ as present (it's already in QRZ)
                existing.markPresent(in: .qrz, context: modelContext)
                updated += 1
                continue
            }

            // Create new QSO
            let newQso = QSO(
                callsign: qrzQso.callsign,
                band: qrzQso.band,
                mode: qrzQso.mode,
                frequency: qrzQso.frequency,
                timestamp: qrzQso.timestamp,
                rstSent: qrzQso.rstSent,
                rstReceived: qrzQso.rstReceived,
                myCallsign: qrzQso.myCallsign ?? myCallsign,
                myGrid: qrzQso.myGrid,
                theirGrid: qrzQso.theirGrid,
                parkReference: qrzQso.parkReference,
                notes: qrzQso.notes,
                importSource: .qrz,
                rawADIF: qrzQso.rawADIF,
                qrzLogId: qrzQso.qrzLogId,
                qrzConfirmed: qrzQso.qrzConfirmed,
                lotwConfirmedDate: qrzQso.lotwConfirmedDate
            )

            modelContext.insert(newQso)

            // Mark as present in QRZ, needs upload to POTA
            createServicePresenceRecords(for: newQso, importedFrom: .qrz)

            imported += 1
        }

        try modelContext.save()

        let result = ImportResult(
            totalRecords: qsos.count,
            imported: imported,
            duplicates: 0,
            errors: 0,
            matched: updated
        )

        lastImportResult = result
        return result
    }

    // MARK: - POTA Import

    func importFromPOTA(qsos: [POTAFetchedQSO]) async throws -> ImportResult {
        isImporting = true
        defer { isImporting = false }

        var imported = 0
        var updated = 0

        // Fetch existing QSOs for matching
        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)
        let byDedupeKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }

        for potaQso in qsos {
            // Build deduplication key
            let roundedTimestamp = potaQso.timestamp.timeIntervalSince1970
            let rounded = Int(roundedTimestamp / 120) * 120
            let dedupeKey = "\(potaQso.callsign.uppercased())|\(potaQso.band.uppercased())|\(potaQso.mode.uppercased())|\(rounded)"

            if let existing = byDedupeKey[dedupeKey]?.first {
                // Update with POTA data if richer
                existing.parkReference = existing.parkReference.nonEmpty ?? potaQso.parkReference
                existing.rstSent = existing.rstSent.nonEmpty ?? potaQso.rstSent
                existing.rstReceived = existing.rstReceived.nonEmpty ?? potaQso.rstReceived
                // Mark POTA as present
                existing.markPresent(in: .pota, context: modelContext)
                updated += 1
                continue
            }

            // Create new QSO
            let newQso = QSO(
                callsign: potaQso.callsign,
                band: potaQso.band,
                mode: potaQso.mode,
                frequency: nil,
                timestamp: potaQso.timestamp,
                rstSent: potaQso.rstSent,
                rstReceived: potaQso.rstReceived,
                myCallsign: potaQso.myCallsign,
                myGrid: nil,
                theirGrid: nil,
                parkReference: potaQso.parkReference,
                notes: nil,
                importSource: .pota,
                rawADIF: nil
            )

            modelContext.insert(newQso)

            // Mark as present in POTA, needs upload to QRZ
            createServicePresenceRecords(for: newQso, importedFrom: .pota)

            imported += 1
        }

        try modelContext.save()

        let result = ImportResult(
            totalRecords: qsos.count,
            imported: imported,
            duplicates: 0,
            errors: 0,
            matched: updated
        )

        lastImportResult = result
        return result
    }
}

enum ImportError: Error, LocalizedError {
    case invalidFile
    case missingTimestamp
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "Could not read the ADIF file"
        case .missingTimestamp:
            return "QSO record missing date/time"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}
