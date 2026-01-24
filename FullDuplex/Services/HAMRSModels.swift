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
    let id: String
    let rev: String?
    let title: String?
    let createdAt: String?
    let updatedAt: String?
    let template: String?
    let myPark: String?
    let myGridsquare: String?
    let operatorCall: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case rev = "_rev"
        case title
        case createdAt
        case updatedAt
        case template
        case myPark
        case myGridsquare
        case operatorCall = "operator"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        rev = try container.decodeIfPresent(String.self, forKey: .rev)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        template = try container.decodeIfPresent(String.self, forKey: .template)
        myPark = try container.decodeIfPresent(String.self, forKey: .myPark)
        myGridsquare = try container.decodeIfPresent(String.self, forKey: .myGridsquare)
        operatorCall = try container.decodeIfPresent(String.self, forKey: .operatorCall)
    }

    init(
        id: String,
        rev: String?,
        title: String?,
        createdAt: String?,
        updatedAt: String?,
        template: String?,
        myPark: String?,
        myGridsquare: String?,
        operatorCall: String?
    ) {
        self.id = id
        self.rev = rev
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.template = template
        self.myPark = myPark
        self.myGridsquare = myGridsquare
        self.operatorCall = operatorCall
    }

    /// Logbook ID without the "LOGBOOK:" prefix
    var logbookId: String {
        if id.hasPrefix("LOGBOOK:") {
            return String(id.dropFirst(8))
        }
        return id
    }
}

// MARK: - QSO

/// HAMRS QSO document from CouchDB
struct HAMRSQSO: Codable {
    let id: String
    let rev: String?
    let createdAt: String?

    // Contact info
    let call: String?
    let name: String?
    let qth: String?
    let state: String?
    let country: String?
    let gridsquare: String?

    // QSO details
    let freq: FrequencyValue?
    let band: String?
    let mode: String?
    let rstSent: String?
    let rstRcvd: String?
    let qsoDate: String?
    let timeOn: String?
    let qsoDateTime: String?
    let txPwr: PowerValue?

    // Program references
    let potaRef: String?
    let sotaRef: String?

    // Other
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case rev = "_rev"
        case createdAt
        case call, name, qth, state, country, gridsquare
        case freq, band, mode, rstSent, rstRcvd
        case qsoDate, timeOn, qsoDateTime, txPwr
        case potaRef, sotaRef, notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        rev = try container.decodeIfPresent(String.self, forKey: .rev)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        call = try container.decodeIfPresent(String.self, forKey: .call)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        qth = try container.decodeIfPresent(String.self, forKey: .qth)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        gridsquare = try container.decodeIfPresent(String.self, forKey: .gridsquare)
        freq = try container.decodeIfPresent(FrequencyValue.self, forKey: .freq)
        band = try container.decodeIfPresent(String.self, forKey: .band)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        rstSent = try container.decodeIfPresent(String.self, forKey: .rstSent)
        rstRcvd = try container.decodeIfPresent(String.self, forKey: .rstRcvd)
        qsoDate = try container.decodeIfPresent(String.self, forKey: .qsoDate)
        timeOn = try container.decodeIfPresent(String.self, forKey: .timeOn)
        qsoDateTime = try container.decodeIfPresent(String.self, forKey: .qsoDateTime)
        txPwr = try container.decodeIfPresent(PowerValue.self, forKey: .txPwr)
        potaRef = try container.decodeIfPresent(String.self, forKey: .potaRef)
        sotaRef = try container.decodeIfPresent(String.self, forKey: .sotaRef)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    /// Extract logbook ID from QSO ID
    /// Format: QSO:LOGBOOK:{logbook-uuid}:{qso-uuid}
    var logbookId: String? {
        let parts = id.split(separator: ":")
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

// MARK: - Flexible Value Types

/// Handles frequency that can be either a number or string in JSON
enum FrequencyValue: Codable {
    case double(Double)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                FrequencyValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Double or String for frequency"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .string(let value):
            return Double(value)
        }
    }
}

/// Handles power that can be either a number or string in JSON
enum PowerValue: Codable {
    case int(Int)
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                PowerValue.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected Int or String for power"
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .string(let value):
            return Int(value)
        }
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
