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

                for destType in DestinationType.allCases {
                    let syncRecord = SyncRecord(destinationType: destType, qso: qso)
                    modelContext.insert(syncRecord)
                    qso.syncRecords.append(syncRecord)
                }

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
            errors: errors
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

                for destType in DestinationType.allCases {
                    let syncRecord = SyncRecord(destinationType: destType, qso: qso)
                    modelContext.insert(syncRecord)
                    qso.syncRecords.append(syncRecord)
                }

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
            errors: errors
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
