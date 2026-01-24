import Foundation

// MARK: - Auth Response

/// Response from HAMRS /api/v1/couchdb_url endpoint
struct HAMRSAuthResponse: Codable {
    let subscribed: Bool
    let url: String?
}

// MARK: - Logbook

/// HAMRS Logbook document from CouchDB
/// Contains activation info that applies to all QSOs in the logbook
struct HAMRSLogbook: Codable {
    let _id: String
    let _rev: String?
    let title: String?
    let createdAt: String?
    let updatedAt: String?
    let template: String?
    let myPark: String?
    let myGridsquare: String?
    let `operator`: String?

    /// Logbook ID without the "LOGBOOK:" prefix
    var logbookId: String {
        if _id.hasPrefix("LOGBOOK:") {
            return String(_id.dropFirst(8))
        }
        return _id
    }
}

// MARK: - QSO

/// HAMRS QSO document from CouchDB
struct HAMRSQSO: Codable {
    let _id: String
    let _rev: String?
    let createdAt: String?

    // Contact info
    let call: String?
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let gridsquare: String?

    // QSO details
    let freq: Double?
    let band: String?
    let mode: String?
    let rstSent: String?
    let rstRcvd: String?
    let qsoDate: String?
    let timeOn: String?
    let qsoDateTime: String?
    let txPwr: Int?

    // Program references
    let potaRef: String?
    let sotaRef: String?

    // Other
    let notes: String?

    /// Extract logbook ID from QSO ID
    /// Format: QSO:LOGBOOK:{logbook-uuid}:{qso-uuid}
    var logbookId: String? {
        let parts = _id.split(separator: ":")
        guard parts.count >= 3, parts[0] == "QSO", parts[1] == "LOGBOOK" else {
            return nil
        }
        return String(parts[2])
    }

    /// Parse timestamp from qsoDateTime (ISO 8601) or fall back to qsoDate + timeOn
    var timestamp: Date? {
        // Try ISO 8601 first
        if let dateTimeStr = qsoDateTime {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateTimeStr) {
                return date
            }
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateTimeStr) {
                return date
            }
        }

        // Fall back to qsoDate + timeOn
        guard let dateStr = qsoDate else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        if let timeStr = timeOn {
            // Try with time
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            if let date = dateFormatter.date(from: "\(dateStr) \(timeStr)") {
                return date
            }
            dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            if let date = dateFormatter.date(from: "\(dateStr) \(timeStr.prefix(5))") {
                return date
            }
        }

        // Date only
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.date(from: dateStr)
    }
}

// MARK: - CouchDB Response Wrappers

/// CouchDB _all_docs response
struct CouchDBAllDocsResponse<T: Codable>: Codable {
    let total_rows: Int
    let offset: Int
    let rows: [CouchDBRow<T>]
}

/// Single row in CouchDB _all_docs response
struct CouchDBRow<T: Codable>: Codable {
    let id: String
    let key: String
    let doc: T?
}
