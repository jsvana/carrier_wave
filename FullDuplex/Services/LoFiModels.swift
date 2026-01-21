import Foundation

// MARK: - Client Registration

struct LoFiRegistrationRequest: Encodable {
    let client: LoFiClientCredentials
    let account: LoFiAccountRequest
    let meta: LoFiMetaRequest
}

struct LoFiClientCredentials: Encodable {
    let key: String
    let name: String
    let secret: String
}

struct LoFiAccountRequest: Encodable {
    let call: String
}

struct LoFiMetaRequest: Encodable {
    let app: String
}

struct LoFiRegistrationResponse: Decodable {
    let token: String
    let client: LoFiClientInfo
    let account: LoFiAccountInfo
    let meta: LoFiMetaInfo
}

struct LoFiClientInfo: Decodable {
    let uuid: String
    let name: String
}

struct LoFiAccountInfo: Decodable {
    let uuid: String
    let call: String
    let name: String?
    let email: String?
    let cutoffDate: String?
    let cutoffDateMillis: Int64?

    enum CodingKeys: String, CodingKey {
        case uuid, call, name, email
        case cutoffDate = "cutoff_date"
        case cutoffDateMillis = "cutoff_date_millis"
    }
}

struct LoFiMetaInfo: Decodable {
    let flags: LoFiSyncFlags
}

struct LoFiSyncFlags: Decodable {
    let suggestedSyncBatchSize: Int
    let suggestedSyncLoopDelay: Int
    let suggestedSyncCheckPeriod: Int

    enum CodingKeys: String, CodingKey {
        case suggestedSyncBatchSize = "suggested_sync_batch_size"
        case suggestedSyncLoopDelay = "suggested_sync_loop_delay"
        case suggestedSyncCheckPeriod = "suggested_sync_check_period"
    }
}

// MARK: - Link Device

struct LoFiLinkDeviceRequest: Encodable {
    let email: String
}

// MARK: - Operations API

struct LoFiOperationsResponse: Decodable {
    let operations: [LoFiOperation]
    let meta: LoFiOperationsMetaWrapper
}

struct LoFiOperationsMetaWrapper: Decodable {
    let operations: LoFiOperationsMeta
}

struct LoFiOperationsMeta: Decodable {
    let totalRecords: Int
    let syncedUntilMillis: Double?
    let syncedUntil: String?
    let syncedSinceMillis: Double?
    let limit: Int
    let recordsLeft: Int
    let nextUpdatedAtMillis: Double?
    let nextSyncedAtMillis: Double?
    let extendedPage: Bool?
    let otherClientsOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case totalRecords = "total_records"
        case syncedUntilMillis = "synced_until_millis"
        case syncedUntil = "synced_until"
        case syncedSinceMillis = "synced_since_millis"
        case limit
        case recordsLeft = "records_left"
        case nextUpdatedAtMillis = "next_updated_at_millis"
        case nextSyncedAtMillis = "next_synced_at_millis"
        case extendedPage = "extended_page"
        case otherClientsOnly = "other_clients_only"
    }
}

struct LoFiOperation: Decodable {
    let uuid: String
    let stationCall: String
    let account: String
    let createdAtMillis: Double
    let createdOnDeviceId: String?
    let updatedAtMillis: Double
    let updatedOnDeviceId: String?
    let syncedAtMillis: Double?
    let title: String?
    let subtitle: String?
    let grid: String?
    let refs: [LoFiOperationRef]
    let qsoCount: Int
    let startAtMillisMin: Double?
    let startAtMillisMax: Double?
    let isNew: Bool?
    let deleted: Int?
    let synced: Int?
}

struct LoFiOperationRef: Decodable {
    let refType: String
    let reference: String?
    let name: String?
    let location: String?
    let label: String?
    let shortLabel: String?
    let program: String?

    enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case name, location, label
        case shortLabel = "short_label"
        case program
    }
}

extension LoFiOperation {
    var potaRef: LoFiOperationRef? {
        refs.first { $0.refType == "potaActivation" || $0.program == "POTA" }
    }

    var sotaRef: LoFiOperationRef? {
        refs.first { $0.refType == "sotaActivation" || $0.program == "SOTA" }
    }
}

// MARK: - QSOs API

struct LoFiQsosResponse: Decodable {
    let qsos: [LoFiQso]
    let meta: LoFiQsosMetaWrapper
}

struct LoFiQsosMetaWrapper: Decodable {
    let qsos: LoFiQsosMeta
}

struct LoFiQsosMeta: Decodable {
    let totalRecords: Int
    let syncedUntilMillis: Double?
    let syncedUntil: String?
    let syncedSinceMillis: Double?
    let limit: Int
    let recordsLeft: Int
    let nextUpdatedAtMillis: Double?
    let nextSyncedAtMillis: Double?
    let extendedPage: Bool?
    let otherClientsOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case totalRecords = "total_records"
        case syncedUntilMillis = "synced_until_millis"
        case syncedUntil = "synced_until"
        case syncedSinceMillis = "synced_since_millis"
        case limit
        case recordsLeft = "records_left"
        case nextUpdatedAtMillis = "next_updated_at_millis"
        case nextSyncedAtMillis = "next_synced_at_millis"
        case extendedPage = "extended_page"
        case otherClientsOnly = "other_clients_only"
    }
}

struct LoFiQso: Decodable {
    let uuid: String
    let operation: String?
    let account: String?
    let createdAtMillis: Double?
    let updatedAtMillis: Double?
    let syncedAtMillis: Double?
    let startAtMillis: Double
    let their: LoFiTheirInfo?
    let our: LoFiOurInfo?
    let band: String?
    let freq: Double?  // kHz
    let mode: String?
    let refs: [LoFiQsoRef]?
    let txPwr: String?
    let notes: String?
    let deleted: Int?
}

struct LoFiTheirInfo: Decodable {
    let call: String?
    let sent: String?
    let guess: LoFiGuessInfo?
}

struct LoFiOurInfo: Decodable {
    let call: String?
    let sent: String?
}

struct LoFiGuessInfo: Decodable {
    let call: String?
    let name: String?
    let state: String?
    let city: String?
    let grid: String?
    let country: String?
    let entityName: String?
    let cqZone: Int?
    let ituZone: Int?
    let dxccCode: Int?
    let continent: String?

    enum CodingKeys: String, CodingKey {
        case call, name, state, city, grid, country
        case entityName = "entity_name"
        case cqZone = "cq_zone"
        case ituZone = "itu_zone"
        case dxccCode = "dxcc_code"
        case continent
    }
}

struct LoFiQsoRef: Decodable {
    let refType: String?
    let reference: String?
    let program: String?
    let ourNumber: String?

    enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case program
        case ourNumber = "our_number"
    }
}

// MARK: - QSO Helpers

extension LoFiQso {
    var theirCall: String? { their?.call }
    var ourCall: String? { our?.call }
    var rstSent: String? { our?.sent }
    var rstRcvd: String? { their?.sent }
    var theirGrid: String? { their?.guess?.grid }
    var theirName: String? { their?.guess?.name }
    var theirState: String? { their?.guess?.state }
    var theirCountry: String? { their?.guess?.entityName }

    /// Frequency in MHz (API returns kHz)
    var freqMHz: Double? { freq.map { $0 / 1000.0 } }

    /// QSO timestamp as Date
    var timestamp: Date {
        Date(timeIntervalSince1970: startAtMillis / 1000.0)
    }

    /// Get their POTA reference
    var theirPotaRef: String? {
        refs?.first { $0.refType == "pota" || $0.program == "POTA" }?.reference
    }

    /// Get our POTA reference from operation refs
    func myPotaRef(from operationRefs: [LoFiOperationRef]) -> String? {
        operationRefs
            .first { $0.refType == "potaActivation" }?
            .reference
    }
}
