import Foundation

// MARK: - LoFiRegistrationRequest

struct LoFiRegistrationRequest: Encodable, Sendable {
    let client: LoFiClientCredentials
    let account: LoFiAccountRequest
    let meta: LoFiMetaRequest
}

// MARK: - LoFiClientCredentials

struct LoFiClientCredentials: Encodable, Sendable {
    let key: String
    let name: String
    let secret: String
}

// MARK: - LoFiAccountRequest

struct LoFiAccountRequest: Encodable, Sendable {
    let call: String
}

// MARK: - LoFiMetaRequest

struct LoFiMetaRequest: Encodable, Sendable {
    let app: String
}

// MARK: - LoFiRegistrationResponse

struct LoFiRegistrationResponse: Decodable, Sendable {
    let token: String
    let client: LoFiClientInfo
    let account: LoFiAccountInfo
    let meta: LoFiMetaInfo
}

// MARK: - LoFiClientInfo

struct LoFiClientInfo: Decodable, Sendable {
    let uuid: String
    let name: String
}

// MARK: - LoFiAccountInfo

struct LoFiAccountInfo: Decodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case uuid
        case call
        case name
        case email
        case cutoffDate = "cutoff_date"
        case cutoffDateMillis = "cutoff_date_millis"
    }

    let uuid: String
    let call: String
    let name: String?
    let email: String?
    let cutoffDate: String?
    let cutoffDateMillis: Int64?
}

// MARK: - LoFiMetaInfo

struct LoFiMetaInfo: Decodable, Sendable {
    let flags: LoFiSyncFlags
}

// MARK: - LoFiSyncFlags

struct LoFiSyncFlags: Decodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case suggestedSyncBatchSize = "suggested_sync_batch_size"
        case suggestedSyncLoopDelay = "suggested_sync_loop_delay"
        case suggestedSyncCheckPeriod = "suggested_sync_check_period"
    }

    let suggestedSyncBatchSize: Int
    let suggestedSyncLoopDelay: Int
    let suggestedSyncCheckPeriod: Int
}

// MARK: - LoFiLinkDeviceRequest

struct LoFiLinkDeviceRequest: Encodable, Sendable {
    let email: String
}

// MARK: - LoFiOperationsResponse

struct LoFiOperationsResponse: Decodable, Sendable {
    let operations: [LoFiOperation]
    let meta: LoFiOperationsMetaWrapper
}

// MARK: - LoFiOperationsMetaWrapper

struct LoFiOperationsMetaWrapper: Decodable, Sendable {
    let operations: LoFiOperationsMeta
}

// MARK: - LoFiOperationsMeta

struct LoFiOperationsMeta: Decodable, Sendable {
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
}

// MARK: - LoFiOperation

struct LoFiOperation: Decodable, Sendable {
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

// MARK: - LoFiOperationRef

struct LoFiOperationRef: Decodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case name, location, label
        case shortLabel = "short_label"
        case program
    }

    let refType: String
    let reference: String?
    let name: String?
    let location: String?
    let label: String?
    let shortLabel: String?
    let program: String?
}

extension LoFiOperation {
    var potaRef: LoFiOperationRef? {
        refs.first { $0.refType == "potaActivation" || $0.program == "POTA" }
    }

    var sotaRef: LoFiOperationRef? {
        refs.first { $0.refType == "sotaActivation" || $0.program == "SOTA" }
    }
}

// MARK: - LoFiQsosResponse

struct LoFiQsosResponse: Decodable, Sendable {
    let qsos: [LoFiQso]
    let meta: LoFiQsosMetaWrapper
}

// MARK: - LoFiQsosMetaWrapper

struct LoFiQsosMetaWrapper: Decodable, Sendable {
    let qsos: LoFiQsosMeta
}

// MARK: - LoFiQsosMeta

struct LoFiQsosMeta: Decodable, Sendable {
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
}

// MARK: - LoFiQso

struct LoFiQso: Decodable, Sendable {
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
    let freq: Double? // kHz
    let mode: String?
    let refs: [LoFiQsoRef]?
    let txPwr: String?
    let notes: String?
    let deleted: Int?
}

// MARK: - LoFiTheirInfo

struct LoFiTheirInfo: Decodable, Sendable {
    let call: String?
    let sent: String?
    let guess: LoFiGuessInfo?
}

// MARK: - LoFiOurInfo

struct LoFiOurInfo: Decodable, Sendable {
    let call: String?
    let sent: String?
}

// MARK: - LoFiGuessInfo

struct LoFiGuessInfo: Decodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case call
        case name
        case state
        case city
        case grid
        case country
        case entityName = "entity_name"
        case cqZone = "cq_zone"
        case ituZone = "itu_zone"
        case dxccCode = "dxcc_code"
        case continent
    }

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
}

// MARK: - LoFiQsoRef

struct LoFiQsoRef: Decodable, Sendable {
    enum CodingKeys: String, CodingKey {
        case refType = "type"
        case reference = "ref"
        case program
        case ourNumber = "our_number"
    }

    let refType: String?
    let reference: String?
    let program: String?
    let ourNumber: String?
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
    var freqMHz: Double? { freq.map { $0 / 1_000.0 } }

    /// QSO timestamp as Date
    var timestamp: Date {
        Date(timeIntervalSince1970: startAtMillis / 1_000.0)
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
