import Foundation
import SwiftData

// MARK: - SyncService Process Methods

extension SyncService {
    struct ProcessResult {
        let created: Int
        let merged: Int
    }

    func processDownloadedQSOs(_ fetched: [FetchedQSO]) throws -> ProcessResult {
        let debugLog = SyncDebugLog.shared

        // Group by deduplication key
        var byKey: [String: [FetchedQSO]] = [:]
        for qso in fetched {
            byKey[qso.deduplicationKey, default: []].append(qso)
        }

        // Count by source for diagnostics
        let breakdownStr = buildSourceBreakdown(fetched)
        debugLog.info("Processing \(fetched.count) QSOs: \(breakdownStr)")

        // Fetch existing QSOs
        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)
        let existingByKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }
        debugLog.info("Found \(existingQSOs.count) existing QSOs in database")

        var created = 0
        var merged = 0

        for (key, fetchedGroup) in byKey {
            if let existing = existingByKey[key]?.first {
                for fetchedQSO in fetchedGroup {
                    mergeIntoExisting(existing: existing, fetched: fetchedQSO)
                }
                merged += 1
            } else {
                createNewQSOFromGroup(fetchedGroup)
                created += 1
            }
        }

        debugLog.info("Process result: created=\(created), merged=\(merged)")
        return ProcessResult(created: created, merged: merged)
    }

    private func buildSourceBreakdown(_ fetched: [FetchedQSO]) -> String {
        var sourceBreakdown: [ServiceType: Int] = [:]
        for qso in fetched {
            sourceBreakdown[qso.source, default: 0] += 1
        }
        return sourceBreakdown.map { "\($0.key.displayName)=\($0.value)" }.joined(separator: ", ")
    }

    private func createNewQSOFromGroup(_ fetchedGroup: [FetchedQSO]) {
        let mergedFetched = mergeFetchedGroup(fetchedGroup)
        let newQSO = createQSO(from: mergedFetched)
        modelContext.insert(newQSO)

        // Create presence records for all sources that had this QSO
        let sources = Set(fetchedGroup.map(\.source))

        // Create presence record for ALL services
        for service in ServiceType.allCases {
            let presence = if sources.contains(service) {
                // QSO came from this service - mark as present
                ServicePresence.downloaded(from: service, qso: newQSO)
            } else if service.supportsUpload {
                // Bidirectional service without this QSO - needs upload
                ServicePresence.needsUpload(to: service, qso: newQSO)
            } else {
                // Download-only service without this QSO - not present, no upload needed
                ServicePresence(serviceType: service, isPresent: false, qso: newQSO)
            }
            modelContext.insert(presence)
            newQSO.servicePresence.append(presence)
        }
    }

    /// Reconcile QRZ presence records against what QRZ actually returned.
    /// Clears isPresent and sets needsUpload for QSOs that we thought were in QRZ but aren't.
    func reconcileQRZPresence(downloadedKeys: Set<String>) throws {
        let descriptor = FetchDescriptor<QSO>()
        let allQSOs = try modelContext.fetch(descriptor)

        for qso in allQSOs {
            guard let presence = qso.presence(for: .qrz), presence.isPresent else {
                continue
            }

            // If QRZ didn't return this QSO, it's not actually there
            if !downloadedKeys.contains(qso.deduplicationKey) {
                presence.isPresent = false
                presence.needsUpload = true
            }
        }
    }

    /// Merge fetched QSO data into existing QSO (richest data wins)
    func mergeIntoExisting(existing: QSO, fetched: FetchedQSO) {
        existing.frequency = existing.frequency ?? fetched.frequency
        existing.rstSent = existing.rstSent.nonEmpty ?? fetched.rstSent
        existing.rstReceived = existing.rstReceived.nonEmpty ?? fetched.rstReceived
        existing.myGrid = existing.myGrid.nonEmpty ?? fetched.myGrid
        existing.theirGrid = existing.theirGrid.nonEmpty ?? fetched.theirGrid
        existing.parkReference = existing.parkReference.nonEmpty ?? fetched.parkReference
        existing.theirParkReference =
            existing.theirParkReference.nonEmpty ?? fetched.theirParkReference
        existing.notes = existing.notes.nonEmpty ?? fetched.notes
        existing.rawADIF = existing.rawADIF.nonEmpty ?? fetched.rawADIF
        existing.name = existing.name.nonEmpty ?? fetched.name
        existing.qth = existing.qth.nonEmpty ?? fetched.qth
        existing.state = existing.state.nonEmpty ?? fetched.state
        existing.country = existing.country.nonEmpty ?? fetched.country
        existing.power = existing.power ?? fetched.power
        existing.sotaRef = existing.sotaRef.nonEmpty ?? fetched.sotaRef

        // QRZ-specific: only update from QRZ source
        if fetched.source == .qrz {
            existing.qrzLogId = existing.qrzLogId ?? fetched.qrzLogId
            existing.qrzConfirmed = existing.qrzConfirmed || fetched.qrzConfirmed
            existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
        }

        // LoTW-specific: update confirmation status
        if fetched.source == .lotw {
            if fetched.lotwConfirmed {
                existing.lotwConfirmed = true
                existing.lotwConfirmedDate = existing.lotwConfirmedDate ?? fetched.lotwConfirmedDate
            }
        }

        // Update or create ServicePresence
        existing.markPresent(in: fetched.source, context: modelContext)
    }

    /// Merge multiple fetched QSOs into one (for new QSO creation)
    func mergeFetchedGroup(_ group: [FetchedQSO]) -> FetchedQSO {
        guard var merged = group.first else {
            fatalError("Empty group in mergeFetchedGroup")
        }

        for other in group.dropFirst() {
            merged = FetchedQSO(
                callsign: merged.callsign,
                band: merged.band,
                mode: merged.mode,
                frequency: merged.frequency ?? other.frequency,
                timestamp: merged.timestamp,
                rstSent: merged.rstSent.nonEmpty ?? other.rstSent,
                rstReceived: merged.rstReceived.nonEmpty ?? other.rstReceived,
                myCallsign: merged.myCallsign.isEmpty ? other.myCallsign : merged.myCallsign,
                myGrid: merged.myGrid.nonEmpty ?? other.myGrid,
                theirGrid: merged.theirGrid.nonEmpty ?? other.theirGrid,
                parkReference: merged.parkReference.nonEmpty ?? other.parkReference,
                theirParkReference: merged.theirParkReference.nonEmpty ?? other.theirParkReference,
                notes: merged.notes.nonEmpty ?? other.notes,
                rawADIF: merged.rawADIF.nonEmpty ?? other.rawADIF,
                name: merged.name.nonEmpty ?? other.name,
                qth: merged.qth.nonEmpty ?? other.qth,
                state: merged.state.nonEmpty ?? other.state,
                country: merged.country.nonEmpty ?? other.country,
                power: merged.power ?? other.power,
                sotaRef: merged.sotaRef.nonEmpty ?? other.sotaRef,
                qrzLogId: merged.qrzLogId ?? other.qrzLogId,
                qrzConfirmed: merged.qrzConfirmed || other.qrzConfirmed,
                lotwConfirmedDate: merged.lotwConfirmedDate ?? other.lotwConfirmedDate,
                lotwConfirmed: merged.lotwConfirmed || other.lotwConfirmed,
                source: merged.source
            )
        }

        return merged
    }

    /// Create a QSO from merged fetched data
    func createQSO(from fetched: FetchedQSO) -> QSO {
        QSO(
            callsign: fetched.callsign,
            band: fetched.band,
            mode: fetched.mode,
            frequency: fetched.frequency,
            timestamp: fetched.timestamp,
            rstSent: fetched.rstSent,
            rstReceived: fetched.rstReceived,
            myCallsign: fetched.myCallsign,
            myGrid: fetched.myGrid,
            theirGrid: fetched.theirGrid,
            parkReference: fetched.parkReference,
            theirParkReference: fetched.theirParkReference,
            notes: fetched.notes,
            importSource: fetched.source.toImportSource,
            rawADIF: fetched.rawADIF,
            name: fetched.name,
            qth: fetched.qth,
            state: fetched.state,
            country: fetched.country,
            power: fetched.power,
            sotaRef: fetched.sotaRef,
            qrzLogId: fetched.qrzLogId,
            qrzConfirmed: fetched.qrzConfirmed,
            lotwConfirmedDate: fetched.lotwConfirmedDate,
            lotwConfirmed: fetched.lotwConfirmed
        )
    }
}
