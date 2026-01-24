import Combine
import Foundation
import SwiftData

// MARK: - Timeout Support

enum SyncTimeoutError: Error, LocalizedError {
    case timeout(service: ServiceType)

    var errorDescription: String? {
        switch self {
        case .timeout(let service):
            return "\(service.displayName) sync timed out"
        }
    }
}

/// Execute an async operation with a timeout
private func withTimeout<T>(
    seconds: TimeInterval,
    service: ServiceType,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw SyncTimeoutError.timeout(service: service)
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

// MARK: - Intermediate Format for Downloaded QSOs

/// Common format for QSOs fetched from any service
struct FetchedQSO {
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let theirParkReference: String?
    let notes: String?
    let rawADIF: String?

    // Contact info
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let power: Int?
    let sotaRef: String?

    // QRZ-specific
    let qrzLogId: String?
    let qrzConfirmed: Bool
    let lotwConfirmedDate: Date?

    // Source tracking
    let source: ServiceType

    var deduplicationKey: String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120
        return "\(callsign.uppercased())|\(band.uppercased())|\(mode.uppercased())|\(rounded)"
    }

    /// Debug dictionary for logging
    var debugFields: [String: String] {
        var fields: [String: String] = [
            "callsign": callsign,
            "band": band,
            "mode": mode,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "myCallsign": myCallsign,
        ]
        if let f = frequency { fields["frequency"] = String(format: "%.4f MHz", f) }
        if let g = myGrid { fields["myGrid"] = g }
        if let g = theirGrid { fields["theirGrid"] = g }
        if let p = parkReference { fields["parkReference"] = p }
        if let p = theirParkReference { fields["theirParkReference"] = p }
        if let r = rstSent { fields["rstSent"] = r }
        if let r = rstReceived { fields["rstReceived"] = r }
        if let id = qrzLogId { fields["qrzLogId"] = id }
        if let n = name { fields["name"] = n }
        if let q = qth { fields["qth"] = q }
        if let s = state { fields["state"] = s }
        if let c = country { fields["country"] = c }
        if let p = power { fields["power"] = String(p) }
        if let s = sotaRef { fields["sotaRef"] = s }
        return fields
    }

    /// Create from QRZ fetched QSO
    static func fromQRZ(_ qrz: QRZFetchedQSO) -> FetchedQSO {
        FetchedQSO(
            callsign: qrz.callsign,
            band: qrz.band,
            mode: qrz.mode,
            frequency: qrz.frequency,
            timestamp: qrz.timestamp,
            rstSent: qrz.rstSent,
            rstReceived: qrz.rstReceived,
            myCallsign: qrz.myCallsign ?? "",
            myGrid: qrz.myGrid,
            theirGrid: qrz.theirGrid,
            parkReference: qrz.parkReference,
            theirParkReference: nil,
            notes: qrz.notes,
            rawADIF: qrz.rawADIF,
            name: nil,
            qth: nil,
            state: nil,
            country: nil,
            power: nil,
            sotaRef: nil,
            qrzLogId: qrz.qrzLogId,
            qrzConfirmed: qrz.qrzConfirmed,
            lotwConfirmedDate: qrz.lotwConfirmedDate,
            source: .qrz
        )
    }

    /// Create from POTA fetched QSO
    static func fromPOTA(_ pota: POTAFetchedQSO) -> FetchedQSO {
        FetchedQSO(
            callsign: pota.callsign,
            band: pota.band,
            mode: pota.mode,
            frequency: nil,
            timestamp: pota.timestamp,
            rstSent: pota.rstSent,
            rstReceived: pota.rstReceived,
            myCallsign: pota.myCallsign,
            myGrid: nil,
            theirGrid: nil,
            parkReference: pota.parkReference,
            theirParkReference: nil,
            notes: nil,
            rawADIF: nil,
            name: nil,
            qth: nil,
            state: nil,
            country: nil,
            power: nil,
            sotaRef: nil,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: nil,
            source: .pota
        )
    }

    /// Create from LoFi fetched QSO
    static func fromLoFi(_ lofi: LoFiQso, operation: LoFiOperation) -> FetchedQSO? {
        guard let callsign = lofi.theirCall,
            let band = lofi.band,
            let mode = lofi.mode
        else {
            return nil
        }

        let parkRef = lofi.myPotaRef(from: operation.refs)

        return FetchedQSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: lofi.freqMHz,
            timestamp: lofi.timestamp,
            rstSent: lofi.rstSent,
            rstReceived: lofi.rstRcvd,
            myCallsign: lofi.ourCall ?? operation.stationCall,
            myGrid: operation.grid,
            theirGrid: lofi.theirGrid,
            parkReference: parkRef,
            theirParkReference: lofi.theirPotaRef,
            notes: lofi.notes,
            rawADIF: nil,
            name: lofi.their?.guess?.name,
            qth: nil,
            state: lofi.their?.guess?.state,
            country: lofi.their?.guess?.country,
            power: nil,
            sotaRef: nil,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: nil,
            source: .lofi
        )
    }

    /// Create from HAMRS fetched QSO with logbook info
    static func fromHAMRS(_ qso: HAMRSQSO, logbook: HAMRSLogbook) -> FetchedQSO? {
        guard let callsign = qso.call,
            let band = qso.band,
            let mode = qso.mode,
            let timestamp = qso.timestamp
        else {
            return nil
        }

        return FetchedQSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: qso.freq?.doubleValue,
            timestamp: timestamp,
            rstSent: qso.rstSent,
            rstReceived: qso.rstRcvd,
            myCallsign: logbook.operatorCall ?? "",
            myGrid: logbook.myGridsquare,
            theirGrid: qso.gridsquare,
            parkReference: logbook.myPark,
            theirParkReference: qso.potaRef,
            notes: qso.notes,
            rawADIF: nil,
            name: qso.name,
            qth: qso.qth,
            state: qso.state,
            country: qso.country,
            power: qso.txPwr?.intValue,
            sotaRef: qso.sotaRef,
            qrzLogId: nil,
            qrzConfirmed: false,
            lotwConfirmedDate: nil,
            source: .hamrs
        )
    }
}

// MARK: - Sync Service

@MainActor
class SyncService: ObservableObject {
    private let modelContext: ModelContext
    private let qrzClient: QRZClient
    private let potaClient: POTAClient
    private let potaAuthService: POTAAuthService
    private let lofiClient: LoFiClient
    private let hamrsClient: HAMRSClient

    /// Timeout for individual service sync operations (in seconds)
    private let syncTimeoutSeconds: TimeInterval = 60

    /// Check if read-only mode is enabled (disables uploads)
    private var isReadOnlyMode: Bool {
        UserDefaults.standard.bool(forKey: "readOnlyMode")
    }

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncPhase: SyncPhase?

    enum SyncPhase: Equatable {
        case downloading(service: ServiceType)
        case processing
        case uploading(service: ServiceType)
    }

    struct SyncResult {
        var downloaded: [ServiceType: Int]
        var uploaded: [ServiceType: Int]
        var errors: [String]
        var newQSOs: Int
        var mergedQSOs: Int
    }

    init(
        modelContext: ModelContext, potaAuthService: POTAAuthService,
        lofiClient: LoFiClient = LoFiClient(),
        hamrsClient: HAMRSClient = HAMRSClient()
    ) {
        self.modelContext = modelContext
        self.qrzClient = QRZClient()
        self.potaAuthService = potaAuthService
        self.potaClient = POTAClient(authService: potaAuthService)
        self.lofiClient = lofiClient
        self.hamrsClient = hamrsClient
    }

    /// Full sync: download from all sources, deduplicate, upload to all destinations
    func syncAll() async throws -> SyncResult {
        isSyncing = true
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting full sync")

        defer {
            isSyncing = false
            syncPhase = nil
            lastSyncDate = Date()
            debugLog.info("Sync complete")
        }

        var result = SyncResult(
            downloaded: [:],
            uploaded: [:],
            errors: [],
            newQSOs: 0,
            mergedQSOs: 0
        )

        // PHASE 1: Download from all sources in parallel
        let downloadResults = await downloadFromAllSources()

        var allFetched: [FetchedQSO] = []
        for (service, fetchResult) in downloadResults {
            switch fetchResult {
            case .success(let qsos):
                result.downloaded[service] = qsos.count
                allFetched.append(contentsOf: qsos)
            case .failure(let error):
                result.errors.append(
                    "\(service.displayName) download: \(error.localizedDescription)")
            }
        }

        // PHASE 2: Process and deduplicate
        syncPhase = .processing
        let processResult = try processDownloadedQSOs(allFetched)
        result.newQSOs = processResult.created
        result.mergedQSOs = processResult.merged

        // PHASE 2.5: Reconcile QRZ presence against what QRZ actually returned
        let qrzDownloadedKeys = Set(
            allFetched.filter { $0.source == .qrz }.map { $0.deduplicationKey })
        if !qrzDownloadedKeys.isEmpty {
            try reconcileQRZPresence(downloadedKeys: qrzDownloadedKeys)
        }

        try modelContext.save()

        // PHASE 3: Upload to all destinations in parallel (unless read-only mode)
        if isReadOnlyMode {
            debugLog.info("Read-only mode enabled, skipping uploads")
        } else {
            let uploadResults = await uploadToAllDestinations()

            for (service, uploadResult) in uploadResults {
                switch uploadResult {
                case .success(let count):
                    result.uploaded[service] = count
                case .failure(let error):
                    result.errors.append(
                        "\(service.displayName) upload: \(error.localizedDescription)")
                }
            }
        }

        try modelContext.save()

        return result
    }

    // MARK: - Download Phase

    private func downloadFromAllSources() async -> [ServiceType: Result<[FetchedQSO], Error>] {
        let timeout = syncTimeoutSeconds
        return await withTaskGroup(of: (ServiceType, Result<[FetchedQSO], Error>).self) { group in
            // QRZ download
            if await qrzClient.hasApiKey() {
                group.addTask {
                    await MainActor.run { self.syncPhase = .downloading(service: .qrz) }
                    let debugLog = await SyncDebugLog.shared
                    await debugLog.info("Starting QRZ download", service: .qrz)
                    do {
                        let qsos = try await withTimeout(seconds: timeout, service: .qrz) {
                            try await self.qrzClient.fetchQSOs(since: nil)
                        }
                        await debugLog.info("Downloaded \(qsos.count) QSOs from QRZ", service: .qrz)
                        let fetched = qsos.map { FetchedQSO.fromQRZ($0) }
                        // Log raw QSOs for debugging
                        for (index, qso) in qsos.prefix(5).enumerated() {
                            await debugLog.logRawQSO(
                                service: .qrz,
                                rawJSON: qso.rawADIF ?? "no raw ADIF",
                                parsedFields: fetched[index].debugFields
                            )
                        }
                        return (.qrz, .success(fetched))
                    } catch {
                        await debugLog.error(
                            "QRZ download failed: \(error.localizedDescription)", service: .qrz)
                        return (.qrz, .failure(error))
                    }
                }
            }

            // POTA download (only if authenticated)
            if potaAuthService.isAuthenticated {
                group.addTask {
                    await MainActor.run { self.syncPhase = .downloading(service: .pota) }
                    let debugLog = await SyncDebugLog.shared
                    await debugLog.info("Starting POTA download", service: .pota)
                    do {
                        let qsos = try await withTimeout(seconds: timeout, service: .pota) {
                            try await self.potaClient.fetchAllQSOs()
                        }
                        await debugLog.info(
                            "Downloaded \(qsos.count) QSOs from POTA", service: .pota)
                        let fetched = qsos.map { FetchedQSO.fromPOTA($0) }
                        // Log raw QSOs for debugging
                        for (index, qso) in fetched.prefix(5).enumerated() {
                            await debugLog.logRawQSO(
                                service: .pota,
                                rawJSON:
                                    "POTA QSO: \(qsos[index].callsign) @ \(qsos[index].timestamp)",
                                parsedFields: qso.debugFields
                            )
                        }
                        return (.pota, .success(fetched))
                    } catch {
                        await debugLog.error(
                            "POTA download failed: \(error.localizedDescription)", service: .pota)
                        return (.pota, .failure(error))
                    }
                }
            }

            // LoFi download (if configured)
            if lofiClient.isConfigured && lofiClient.isLinked {
                group.addTask {
                    await MainActor.run { self.syncPhase = .downloading(service: .lofi) }
                    let debugLog = await SyncDebugLog.shared
                    await debugLog.info("Starting LoFi download", service: .lofi)
                    do {
                        let qsos = try await withTimeout(seconds: timeout, service: .lofi) {
                            try await self.lofiClient.fetchAllQsosSinceLastSync()
                        }
                        await debugLog.info(
                            "Downloaded \(qsos.count) raw QSOs from LoFi API", service: .lofi)

                        // Track how many pass the filter
                        var skippedCount = 0
                        var fetchedList: [FetchedQSO] = []
                        for (lofiQso, operation) in qsos {
                            if let fetched = FetchedQSO.fromLoFi(lofiQso, operation: operation) {
                                fetchedList.append(fetched)
                            } else {
                                skippedCount += 1
                                // Log why it was skipped
                                await debugLog.warning(
                                    "Skipped QSO: call=\(lofiQso.theirCall ?? "nil"), band=\(lofiQso.band ?? "nil"), mode=\(lofiQso.mode ?? "nil")",
                                    service: .lofi)
                            }
                        }
                        let fetched = fetchedList
                        await debugLog.info(
                            "After filtering: \(fetched.count) valid, \(skippedCount) skipped",
                            service: .lofi)
                        // Log raw QSOs for debugging
                        for (index, (lofiQso, op)) in qsos.prefix(5).enumerated() {
                            let rawJSON = """
                                {
                                  "uuid": "\(lofiQso.uuid)",
                                  "startAtMillis": \(lofiQso.startAtMillis),
                                  "band": "\(lofiQso.band ?? "nil")",
                                  "mode": "\(lofiQso.mode ?? "nil")",
                                  "freq": \(lofiQso.freq.map { String($0) } ?? "nil"),
                                  "their": { "call": "\(lofiQso.their?.call ?? "nil")" },
                                  "operation": "\(op.uuid)"
                                }
                                """
                            if index < fetched.count {
                                await debugLog.logRawQSO(
                                    service: .lofi,
                                    rawJSON: rawJSON,
                                    parsedFields: fetched[index].debugFields
                                )
                            }
                        }
                        return (.lofi, .success(fetched))
                    } catch {
                        await debugLog.error(
                            "LoFi download failed: \(error.localizedDescription)", service: .lofi)
                        return (.lofi, .failure(error))
                    }
                }
            }

            // HAMRS download (if configured)
            if hamrsClient.isConfigured {
                group.addTask {
                    await MainActor.run { self.syncPhase = .downloading(service: .hamrs) }
                    let debugLog = await SyncDebugLog.shared
                    await debugLog.info("Starting HAMRS download", service: .hamrs)
                    do {
                        let qsos = try await withTimeout(seconds: timeout, service: .hamrs) {
                            try await self.hamrsClient.fetchAllQSOs()
                        }
                        await debugLog.info(
                            "Downloaded \(qsos.count) raw QSOs from HAMRS", service: .hamrs)

                        // Convert to FetchedQSO format
                        var skippedCount = 0
                        var fetchedList: [FetchedQSO] = []
                        for (hamrsQso, logbook) in qsos {
                            if let fetched = FetchedQSO.fromHAMRS(hamrsQso, logbook: logbook) {
                                fetchedList.append(fetched)
                            } else {
                                skippedCount += 1
                                await debugLog.warning(
                                    "Skipped QSO: call=\(hamrsQso.call ?? "nil"), band=\(hamrsQso.band ?? "nil"), mode=\(hamrsQso.mode ?? "nil")",
                                    service: .hamrs)
                            }
                        }
                        await debugLog.info(
                            "After filtering: \(fetchedList.count) valid, \(skippedCount) skipped",
                            service: .hamrs)

                        // Log sample QSOs for debugging
                        for fetched in fetchedList.prefix(5) {
                            await debugLog.logRawQSO(
                                service: .hamrs,
                                rawJSON: "HAMRS QSO: \(fetched.callsign) @ \(fetched.timestamp)",
                                parsedFields: fetched.debugFields
                            )
                        }
                        return (.hamrs, .success(fetchedList))
                    } catch HAMRSError.subscriptionInactive {
                        await debugLog.warning(
                            "HAMRS subscription inactive - skipping download", service: .hamrs)
                        return (.hamrs, .success([]))
                    } catch {
                        await debugLog.error(
                            "HAMRS download failed: \(error.localizedDescription)", service: .hamrs)
                        return (.hamrs, .failure(error))
                    }
                }
            }

            var results: [ServiceType: Result<[FetchedQSO], Error>] = [:]
            for await (service, result) in group {
                results[service] = result
            }
            return results
        }
    }

    // MARK: - Process Phase

    private struct ProcessResult {
        let created: Int
        let merged: Int
    }

    private func processDownloadedQSOs(_ fetched: [FetchedQSO]) throws -> ProcessResult {
        let debugLog = SyncDebugLog.shared

        // Group by deduplication key
        var byKey: [String: [FetchedQSO]] = [:]
        for qso in fetched {
            byKey[qso.deduplicationKey, default: []].append(qso)
        }

        // Count by source for diagnostics
        var sourceBreakdown: [ServiceType: Int] = [:]
        for qso in fetched {
            sourceBreakdown[qso.source, default: 0] += 1
        }
        debugLog.info(
            "Processing \(fetched.count) QSOs: \(sourceBreakdown.map { "\($0.key.displayName)=\($0.value)" }.joined(separator: ", "))"
        )

        // Fetch existing QSOs
        let descriptor = FetchDescriptor<QSO>()
        let existingQSOs = try modelContext.fetch(descriptor)
        let existingByKey = Dictionary(grouping: existingQSOs) { $0.deduplicationKey }
        debugLog.info("Found \(existingQSOs.count) existing QSOs in database")

        var created = 0
        var merged = 0

        for (key, fetchedGroup) in byKey {
            if let existing = existingByKey[key]?.first {
                // Merge into existing
                for fetched in fetchedGroup {
                    mergeIntoExisting(existing: existing, fetched: fetched)
                }
                merged += 1
            } else {
                // Create new QSO from merged fetched data
                let mergedFetched = mergeFetchedGroup(fetchedGroup)
                let newQSO = createQSO(from: mergedFetched)
                modelContext.insert(newQSO)

                // Create presence records for all sources that had this QSO
                let sources = Set(fetchedGroup.map(\.source))
                for source in sources {
                    let presence = ServicePresence.downloaded(from: source, qso: newQSO)
                    modelContext.insert(presence)
                    newQSO.servicePresence.append(presence)
                }

                // Mark as needing upload to services that don't have it
                for service in ServiceType.allCases
                where service.supportsUpload && !sources.contains(service) {
                    let presence = ServicePresence.needsUpload(to: service, qso: newQSO)
                    modelContext.insert(presence)
                    newQSO.servicePresence.append(presence)
                }

                created += 1
            }
        }

        debugLog.info("Process result: created=\(created), merged=\(merged)")

        return ProcessResult(created: created, merged: merged)
    }

    /// Reconcile QRZ presence records against what QRZ actually returned.
    /// Clears isPresent and sets needsUpload for QSOs that we thought were in QRZ but aren't.
    private func reconcileQRZPresence(downloadedKeys: Set<String>) throws {
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
    private func mergeIntoExisting(existing: QSO, fetched: FetchedQSO) {
        // Merge fields - keep richest data
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

        // Update or create ServicePresence
        existing.markPresent(in: fetched.source, context: modelContext)
    }

    /// Merge multiple fetched QSOs into one (for new QSO creation)
    private func mergeFetchedGroup(_ group: [FetchedQSO]) -> FetchedQSO {
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
                source: merged.source
            )
        }

        return merged
    }

    /// Create a QSO from merged fetched data
    private func createQSO(from fetched: FetchedQSO) -> QSO {
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
            lotwConfirmedDate: fetched.lotwConfirmedDate
        )
    }

    // MARK: - Upload Phase

    private func uploadToAllDestinations() async -> [ServiceType: Result<Int, Error>] {
        // Fetch QSOs needing upload
        let qsosNeedingUpload = try? fetchQSOsNeedingUpload()
        let timeout = syncTimeoutSeconds

        return await withTaskGroup(of: (ServiceType, Result<Int, Error>).self) { group in
            // QRZ upload
            if await qrzClient.hasApiKey() {
                let qrzQSOs = qsosNeedingUpload?.filter { $0.needsUpload(to: .qrz) } ?? []
                if !qrzQSOs.isEmpty {
                    group.addTask {
                        await MainActor.run { self.syncPhase = .uploading(service: .qrz) }
                        do {
                            let count = try await withTimeout(seconds: timeout, service: .qrz) {
                                try await self.uploadToQRZ(qsos: qrzQSOs)
                            }
                            return (.qrz, .success(count))
                        } catch {
                            return (.qrz, .failure(error))
                        }
                    }
                }
            }

            // POTA upload (only if authenticated)
            if potaAuthService.isAuthenticated {
                let potaQSOs =
                    qsosNeedingUpload?.filter {
                        $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
                    } ?? []
                if !potaQSOs.isEmpty {
                    group.addTask {
                        await MainActor.run { self.syncPhase = .uploading(service: .pota) }
                        do {
                            let count = try await withTimeout(seconds: timeout, service: .pota) {
                                try await self.uploadToPOTA(qsos: potaQSOs)
                            }
                            return (.pota, .success(count))
                        } catch {
                            return (.pota, .failure(error))
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
    }

    private func fetchQSOsNeedingUpload() throws -> [QSO] {
        let descriptor = FetchDescriptor<QSO>()
        let allQSOs = try modelContext.fetch(descriptor)
        return allQSOs.filter { qso in
            qso.servicePresence.contains { $0.needsUpload }
        }
    }

    private func uploadToQRZ(qsos: [QSO]) async throws -> Int {
        let batchSize = 50
        var totalUploaded = 0

        for batch in stride(from: 0, to: qsos.count, by: batchSize) {
            let end = min(batch + batchSize, qsos.count)
            let batchQSOs = Array(qsos[batch..<end])

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

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR"]

    private func uploadToPOTA(qsos: [QSO]) async throws -> Int {
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

    // MARK: - Single Service Sync (for UI buttons)

    /// Sync only with QRZ (download then upload)
    func syncQRZ() async throws -> (downloaded: Int, uploaded: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
        }

        var downloaded = 0
        var uploaded = 0

        // Download with timeout
        syncPhase = .downloading(service: .qrz)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .qrz) {
            try await self.qrzClient.fetchQSOs(since: nil)
        }
        let fetched = qsos.map { FetchedQSO.fromQRZ($0) }

        syncPhase = .processing
        let processResult = try processDownloadedQSOs(fetched)
        downloaded = processResult.created

        // Reconcile QRZ presence against what QRZ actually returned
        let qrzDownloadedKeys = Set(fetched.map { $0.deduplicationKey })
        try reconcileQRZPresence(downloadedKeys: qrzDownloadedKeys)

        try modelContext.save()

        // Upload with timeout (unless read-only mode)
        if !isReadOnlyMode {
            syncPhase = .uploading(service: .qrz)
            let qsosToUpload = try fetchQSOsNeedingUpload().filter { $0.needsUpload(to: .qrz) }
            uploaded = try await withTimeout(seconds: syncTimeoutSeconds, service: .qrz) {
                try await self.uploadToQRZ(qsos: qsosToUpload)
            }
            try modelContext.save()
        }

        return (downloaded, uploaded)
    }

    /// Sync only with POTA (download then upload)
    func syncPOTA() async throws -> (downloaded: Int, uploaded: Int) {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
        }

        var downloaded = 0
        var uploaded = 0

        // Download with timeout
        syncPhase = .downloading(service: .pota)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .pota) {
            try await self.potaClient.fetchAllQSOs()
        }
        let fetched = qsos.map { FetchedQSO.fromPOTA($0) }

        syncPhase = .processing
        let processResult = try processDownloadedQSOs(fetched)
        downloaded = processResult.created
        try modelContext.save()

        // Upload with timeout (unless read-only mode)
        if !isReadOnlyMode {
            syncPhase = .uploading(service: .pota)
            let qsosToUpload = try fetchQSOsNeedingUpload().filter {
                $0.needsUpload(to: .pota) && $0.parkReference?.isEmpty == false
            }
            uploaded = try await withTimeout(seconds: syncTimeoutSeconds, service: .pota) {
                try await self.uploadToPOTA(qsos: qsosToUpload)
            }
            try modelContext.save()
        }

        return (downloaded, uploaded)
    }

    /// Sync only with LoFi (download only)
    func syncLoFi() async throws -> Int {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
        }

        // Download with timeout
        syncPhase = .downloading(service: .lofi)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .lofi) {
            try await self.lofiClient.fetchAllQsosSinceLastSync()
        }
        let fetched = qsos.compactMap { FetchedQSO.fromLoFi($0.0, operation: $0.1) }

        syncPhase = .processing
        let processResult = try processDownloadedQSOs(fetched)
        try modelContext.save()

        return processResult.created
    }

    /// Sync only with HAMRS (download only)
    func syncHAMRS() async throws -> Int {
        isSyncing = true
        defer {
            isSyncing = false
            syncPhase = nil
        }

        // Download with timeout
        syncPhase = .downloading(service: .hamrs)
        let qsos = try await withTimeout(seconds: syncTimeoutSeconds, service: .hamrs) {
            try await self.hamrsClient.fetchAllQSOs()
        }
        let fetched = qsos.compactMap { FetchedQSO.fromHAMRS($0.0, logbook: $0.1) }

        syncPhase = .processing
        let processResult = try processDownloadedQSOs(fetched)
        try modelContext.save()

        return processResult.created
    }

    /// Download from all sources without uploading (debug mode)
    func downloadOnly() async throws -> SyncResult {
        isSyncing = true
        let debugLog = SyncDebugLog.shared
        debugLog.info("Starting download-only sync")

        defer {
            isSyncing = false
            syncPhase = nil
            lastSyncDate = Date()
            debugLog.info("Download-only sync complete")
        }

        var result = SyncResult(
            downloaded: [:],
            uploaded: [:],
            errors: [],
            newQSOs: 0,
            mergedQSOs: 0
        )

        // PHASE 1: Download from all sources in parallel
        let downloadResults = await downloadFromAllSources()

        var allFetched: [FetchedQSO] = []
        for (service, fetchResult) in downloadResults {
            switch fetchResult {
            case .success(let qsos):
                result.downloaded[service] = qsos.count
                allFetched.append(contentsOf: qsos)
            case .failure(let error):
                result.errors.append(
                    "\(service.displayName) download: \(error.localizedDescription)")
            }
        }

        // PHASE 2: Process and deduplicate
        syncPhase = .processing
        let processResult = try processDownloadedQSOs(allFetched)
        result.newQSOs = processResult.created
        result.mergedQSOs = processResult.merged

        try modelContext.save()

        // Skip upload phase
        return result
    }
}
