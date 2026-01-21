import Foundation

enum QRZError: Error, LocalizedError {
    case invalidApiKey
    case sessionExpired
    case uploadFailed(String)
    case networkError(Error)
    case invalidResponse
    case noQSOs

    var errorDescription: String? {
        switch self {
        case .invalidApiKey:
            return "Invalid QRZ API key"
        case .sessionExpired:
            return "QRZ session expired, please re-authenticate"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from QRZ"
        case .noQSOs:
            return "No QSOs found"
        }
    }
}

/// Response from QRZ STATUS action
struct QRZStatusResponse {
    let callsign: String
    let qsoCount: Int
    let confirmedCount: Int
}

/// A QSO fetched from QRZ logbook
struct QRZFetchedQSO {
    let callsign: String
    let band: String
    let mode: String
    let frequency: Double?
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String?
    let myGrid: String?
    let theirGrid: String?
    let parkReference: String?
    let notes: String?
    let qrzLogId: String?
    let qrzConfirmed: Bool
    let lotwConfirmedDate: Date?
    let rawADIF: String
}

actor QRZClient {
    private let baseURL = "https://logbook.qrz.com/api"
    private let keychain = KeychainHelper.shared
    private let userAgent = "FullDuplex/1.0"

    // MARK: - Response Parsing

    static func parseResponse(_ response: String) -> [String: String] {
        var result: [String: String] = [:]
        let pairs = response.components(separatedBy: "&")

        for pair in pairs {
            let parts = pair.components(separatedBy: "=")
            if parts.count == 2 {
                result[parts[0]] = parts[1]
            } else if parts.count > 2 {
                // Handle values containing "="
                result[parts[0]] = parts.dropFirst().joined(separator: "=")
            }
        }

        return result
    }

    // MARK: - API Key Management

    func saveApiKey(_ key: String) throws {
        try keychain.save(key, for: KeychainHelper.Keys.qrzApiKey)
    }

    func getApiKey() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.qrzApiKey)
    }

    func hasApiKey() -> Bool {
        do {
            _ = try keychain.readString(for: KeychainHelper.Keys.qrzApiKey)
            return true
        } catch {
            return false
        }
    }

    func clearApiKey() {
        try? keychain.delete(for: KeychainHelper.Keys.qrzApiKey)
    }

    func saveCallsign(_ callsign: String) throws {
        try keychain.save(callsign, for: KeychainHelper.Keys.qrzCallsign)
    }

    func getCallsign() -> String? {
        try? keychain.readString(for: KeychainHelper.Keys.qrzCallsign)
    }

    // MARK: - Stats Tracking

    func getTotalUploaded() -> Int {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.qrzTotalUploaded),
              let count = Int(str) else {
            return 0
        }
        return count
    }

    func getTotalDownloaded() -> Int {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.qrzTotalDownloaded),
              let count = Int(str) else {
            return 0
        }
        return count
    }

    func getLastUploadDate() -> Date? {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.qrzLastUploadDate),
              let timestamp = Double(str) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    func getLastDownloadDate() -> Date? {
        guard let str = try? keychain.readString(for: KeychainHelper.Keys.qrzLastDownloadDate),
              let timestamp = Double(str) else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private func incrementUploaded(by count: Int) {
        let current = getTotalUploaded()
        try? keychain.save(String(current + count), for: KeychainHelper.Keys.qrzTotalUploaded)
        try? keychain.save(String(Date().timeIntervalSince1970), for: KeychainHelper.Keys.qrzLastUploadDate)
    }

    private func incrementDownloaded(by count: Int) {
        let current = getTotalDownloaded()
        try? keychain.save(String(current + count), for: KeychainHelper.Keys.qrzTotalDownloaded)
        try? keychain.save(String(Date().timeIntervalSince1970), for: KeychainHelper.Keys.qrzLastDownloadDate)
    }

    // MARK: - API Methods

    /// Validate an API key by calling STATUS action
    func validateApiKey(_ key: String) async throws -> QRZStatusResponse {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "ACTION", value: "STATUS"),
            URLQueryItem(name: "KEY", value: key)
        ]

        guard let url = components.url else {
            throw QRZError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse
        }

        let parsed = Self.parseResponse(responseString)

        guard parsed["RESULT"] == "OK" else {
            throw QRZError.invalidApiKey
        }

        guard let callsign = parsed["CALLSIGN"] else {
            throw QRZError.invalidResponse
        }

        let qsoCount = Int(parsed["COUNT"] ?? "0") ?? 0
        let confirmedCount = Int(parsed["CONFIRMED"] ?? "0") ?? 0

        return QRZStatusResponse(
            callsign: callsign,
            qsoCount: qsoCount,
            confirmedCount: confirmedCount
        )
    }

    /// Upload QSOs to QRZ logbook
    func uploadQSOs(_ qsos: [QSO]) async throws -> (uploaded: Int, duplicates: Int) {
        guard !qsos.isEmpty else {
            return (uploaded: 0, duplicates: 0)
        }

        let apiKey = try getApiKey()

        // Convert QSOs to ADIF
        let adifContent = qsos.map { qso in
            qso.rawADIF ?? generateADIF(for: qso)
        }.joined(separator: "\n")

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "ACTION", value: "INSERT"),
            URLQueryItem(name: "KEY", value: apiKey),
            URLQueryItem(name: "ADIF", value: adifContent)
        ]

        guard let url = components.url else {
            throw QRZError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse
        }

        let parsed = Self.parseResponse(responseString)

        if parsed["RESULT"] == "AUTH" {
            throw QRZError.sessionExpired
        }

        guard parsed["RESULT"] == "OK" else {
            throw QRZError.uploadFailed(parsed["REASON"] ?? "Unknown error")
        }

        let count = Int(parsed["COUNT"] ?? "0") ?? 0
        let dupes = Int(parsed["DUPES"] ?? "0") ?? 0

        if count > 0 {
            incrementUploaded(by: count)
        }

        return (uploaded: count, duplicates: dupes)
    }

    /// Fetch QSOs from QRZ logbook with pagination
    func fetchQSOs(since: Date? = nil) async throws -> [QRZFetchedQSO] {
        let apiKey = try getApiKey()

        var allQSOs: [QRZFetchedQSO] = []
        var offset = 0
        let pageSize = 250

        while true {
            // Build OPTION parameter with comma-separated filters
            var optionParts = ["MAX:\(pageSize)", "OFFSET:\(offset)"]

            // Add MODSINCE filter if date provided
            if let since = since {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone(identifier: "UTC")
                optionParts.append("MODSINCE:\(formatter.string(from: since))")
            }

            var components = URLComponents(string: baseURL)!
            components.queryItems = [
                URLQueryItem(name: "ACTION", value: "FETCH"),
                URLQueryItem(name: "KEY", value: apiKey),
                URLQueryItem(name: "OPTION", value: optionParts.joined(separator: ","))
            ]

            guard let url = components.url else {
                throw QRZError.invalidResponse
            }

            var request = URLRequest(url: url)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

            let (data, _) = try await URLSession.shared.data(for: request)

            guard let responseString = String(data: data, encoding: .utf8) else {
                throw QRZError.invalidResponse
            }

            let parsed = Self.parseResponse(responseString)

            if parsed["RESULT"] == "AUTH" {
                throw QRZError.sessionExpired
            }

            // "no log entries found" is not an error, just means no more results
            if let reason = parsed["REASON"], reason.lowercased().contains("no log entries found") {
                break
            }

            guard parsed["RESULT"] == "OK" else {
                throw QRZError.uploadFailed(parsed["REASON"] ?? "Unknown error")
            }

            guard let encodedADIF = parsed["ADIF"] else {
                break
            }

            let adif = decodeADIF(encodedADIF)
            let pageQSOs = parseADIFRecords(adif)

            if pageQSOs.isEmpty {
                break
            }

            allQSOs.append(contentsOf: pageQSOs)

            // If we got fewer than the page size, we've reached the end
            if pageQSOs.count < pageSize {
                break
            }

            offset += pageSize

            // Small delay between pages to be nice to the API
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }

        if !allQSOs.isEmpty {
            incrementDownloaded(by: allQSOs.count)
        }

        return allQSOs
    }

    // MARK: - ADIF Helpers

    /// Decode ADIF from QRZ response (URL decode then HTML entity decode)
    private func decodeADIF(_ encoded: String) -> String {
        // First URL decode
        var decoded = encoded.removingPercentEncoding ?? encoded

        // Then decode HTML entities
        let htmlEntities: [(String, String)] = [
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&#x27;", "'")
        ]

        for (entity, char) in htmlEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: char)
        }

        return decoded
    }

    /// Parse ADIF string into QRZFetchedQSO records
    private func parseADIFRecords(_ adif: String) -> [QRZFetchedQSO] {
        var qsos: [QRZFetchedQSO] = []

        // Split by end of record marker
        let records = adif.lowercased().contains("<eor>")
            ? adif.components(separatedBy: "<eor>").compactMap { $0.isEmpty ? nil : $0 }
            : adif.components(separatedBy: "<EOR>").compactMap { $0.isEmpty ? nil : $0 }

        for record in records {
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                continue
            }

            let fields = parseADIFFields(record)

            guard let callsign = fields["CALL"] ?? fields["call"],
                  let band = fields["BAND"] ?? fields["band"],
                  let mode = fields["MODE"] ?? fields["mode"] else {
                continue
            }

            let timestamp = parseTimestamp(
                date: fields["QSO_DATE"] ?? fields["qso_date"],
                time: fields["TIME_ON"] ?? fields["time_on"]
            ) ?? Date()

            // Parse frequency (convert MHz to kHz if present)
            var frequency: Double?
            if let freqStr = fields["FREQ"] ?? fields["freq"], let freq = Double(freqStr) {
                frequency = freq * 1000 // MHz to kHz
            }

            // Check QRZ confirmation status
            let qrzStatus = fields["APP_QRZLOG_STATUS"] ?? fields["app_qrzlog_status"]
            let qrzConfirmed = qrzStatus?.uppercased() == "C"

            // Parse LoTW confirmed date
            let lotwDate = parseLotwDate(fields["LOTW_QSL_RCVD"] ?? fields["lotw_qsl_rcvd"])

            let qso = QRZFetchedQSO(
                callsign: callsign.uppercased(),
                band: band.uppercased(),
                mode: mode.uppercased(),
                frequency: frequency,
                timestamp: timestamp,
                rstSent: fields["RST_SENT"] ?? fields["rst_sent"],
                rstReceived: fields["RST_RCVD"] ?? fields["rst_rcvd"],
                myCallsign: fields["STATION_CALLSIGN"] ?? fields["station_callsign"],
                myGrid: fields["MY_GRIDSQUARE"] ?? fields["my_gridsquare"],
                theirGrid: fields["GRIDSQUARE"] ?? fields["gridsquare"],
                parkReference: fields["SIG_INFO"] ?? fields["sig_info"],
                notes: fields["COMMENT"] ?? fields["comment"],
                qrzLogId: fields["APP_QRZLOG_LOGID"] ?? fields["app_qrzlog_logid"],
                qrzConfirmed: qrzConfirmed,
                lotwConfirmedDate: lotwDate,
                rawADIF: record
            )
            qsos.append(qso)
        }

        return qsos
    }

    /// Parse ADIF fields from a record string
    private func parseADIFFields(_ record: String) -> [String: String] {
        var fields: [String: String] = [:]

        // Match <FIELD:length>value pattern
        let pattern = #"<(\w+):(\d+)(?::\w+)?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return fields
        }

        let nsRecord = record as NSString
        let matches = regex.matches(in: record, options: [], range: NSRange(location: 0, length: nsRecord.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }

            let fieldNameRange = match.range(at: 1)
            let lengthRange = match.range(at: 2)

            let fieldName = nsRecord.substring(with: fieldNameRange)
            guard let length = Int(nsRecord.substring(with: lengthRange)) else { continue }

            // Value starts right after the closing >
            let valueStart = match.range.location + match.range.length
            if valueStart + length <= nsRecord.length {
                let valueRange = NSRange(location: valueStart, length: length)
                let value = nsRecord.substring(with: valueRange)
                fields[fieldName] = value
            }
        }

        return fields
    }

    /// Parse ADIF date/time fields into Date
    private func parseTimestamp(date: String?, time: String?) -> Date? {
        guard let date = date else { return nil }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")

        if let time = time, time.count >= 4 {
            formatter.dateFormat = "yyyyMMddHHmm"
            return formatter.date(from: date + time.prefix(4))
        } else {
            formatter.dateFormat = "yyyyMMdd"
            return formatter.date(from: date)
        }
    }

    /// Parse LoTW date string
    private func parseLotwDate(_ dateStr: String?) -> Date? {
        guard let dateStr = dateStr, !dateStr.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"

        return formatter.date(from: dateStr)
    }

    /// Generate ADIF for a QSO
    private func generateADIF(for qso: QSO) -> String {
        var fields: [String] = []

        func addField(_ name: String, _ value: String?) {
            guard let value = value, !value.isEmpty else { return }
            fields.append("<\(name):\(value.count)>\(value)")
        }

        addField("call", qso.callsign)
        addField("band", qso.band)
        addField("mode", qso.mode)

        if let freq = qso.frequency {
            addField("freq", String(format: "%.4f", freq / 1000)) // kHz to MHz
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        addField("qso_date", dateFormatter.string(from: qso.timestamp))

        dateFormatter.dateFormat = "HHmm"
        addField("time_on", dateFormatter.string(from: qso.timestamp))

        addField("rst_sent", qso.rstSent)
        addField("rst_rcvd", qso.rstReceived)
        addField("station_callsign", qso.myCallsign)
        addField("my_gridsquare", qso.myGrid)
        addField("gridsquare", qso.theirGrid)
        addField("sig_info", qso.parkReference)
        addField("comment", qso.notes)

        return fields.joined(separator: " ") + " <eor>"
    }

    // MARK: - Session Management

    func logout() {
        clearApiKey()
        try? keychain.delete(for: KeychainHelper.Keys.qrzCallsign)
        try? keychain.delete(for: KeychainHelper.Keys.qrzTotalUploaded)
        try? keychain.delete(for: KeychainHelper.Keys.qrzTotalDownloaded)
        try? keychain.delete(for: KeychainHelper.Keys.qrzLastUploadDate)
        try? keychain.delete(for: KeychainHelper.Keys.qrzLastDownloadDate)
        // Also clear deprecated session-based keys
        try? keychain.delete(for: KeychainHelper.Keys.qrzSessionKey)
        try? keychain.delete(for: KeychainHelper.Keys.qrzUsername)
    }
}
