import Foundation

enum QRZError: Error, LocalizedError {
    case invalidApiKey
    case sessionExpired
    case uploadFailed(String)
    case fetchFailed(String)
    case networkError(Error)
    case invalidResponse(String)
    case noQSOs

    var errorDescription: String? {
        switch self {
        case .invalidApiKey:
            return "Invalid QRZ API key"
        case .sessionExpired:
            return "QRZ session expired, please re-authenticate"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .fetchFailed(let reason):
            return "Fetch failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let details):
            return "Invalid response from QRZ: \(details)"
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

    /// Parse QRZ API response. ADIF field needs special handling as it contains & characters.
    static func parseResponse(_ response: String) -> [String: String] {
        var result: [String: String] = [:]

        // Check if there's an ADIF field - it needs special handling
        // The ADIF field contains HTML entities like &lt; which would break normal parsing
        if let adifRange = response.range(of: "ADIF=") {
            // Parse everything before ADIF normally
            let beforeADIF = String(response[..<adifRange.lowerBound])
            for pair in beforeADIF.components(separatedBy: "&") {
                if pair.isEmpty { continue }
                let parts = pair.components(separatedBy: "=")
                if parts.count >= 2 {
                    result[parts[0]] = parts.dropFirst().joined(separator: "=")
                }
            }

            // The ADIF value is everything after "ADIF="
            let adifValue = String(response[adifRange.upperBound...])
            result["ADIF"] = adifValue
        } else {
            // No ADIF field, parse normally
            for pair in response.components(separatedBy: "&") {
                let parts = pair.components(separatedBy: "=")
                if parts.count >= 2 {
                    result[parts[0]] = parts.dropFirst().joined(separator: "=")
                }
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

    // MARK: - API Methods

    /// Validate an API key by calling STATUS action
    func validateApiKey(_ key: String) async throws -> QRZStatusResponse {
        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Form-encode the body
        let formData = [
            "KEY": key,
            "ACTION": "STATUS"
        ]
        request.httpBody = formEncode(formData).data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse("Cannot decode response as UTF-8, \(data.count) bytes")
        }

        let parsed = Self.parseResponse(responseString)

        guard parsed["RESULT"] == "OK" else {
            throw QRZError.invalidApiKey
        }

        guard let callsign = parsed["CALLSIGN"] else {
            throw QRZError.invalidResponse("No callsign in response: \(responseString.prefix(200))")
        }

        let qsoCount = Int(parsed["COUNT"] ?? "0") ?? 0
        let confirmedCount = Int(parsed["CONFIRMED"] ?? "0") ?? 0

        return QRZStatusResponse(
            callsign: callsign,
            qsoCount: qsoCount,
            confirmedCount: confirmedCount
        )
    }

    /// Form-encode a dictionary for POST body (application/x-www-form-urlencoded)
    private func formEncode(_ params: [String: String]) -> String {
        // For form encoding, we need a restricted character set
        // Only alphanumerics, *, -, ., _ are safe; space becomes +
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "*-._")

        return params.map { key, value in
            let escapedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let escapedValue = value
                .replacingOccurrences(of: " ", with: "+")
                .addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(escapedKey)=\(escapedValue)"
        }.joined(separator: "&")
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

        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Form-encode the body
        // Use REPLACE option to handle duplicates gracefully
        let formData = [
            "KEY": apiKey,
            "ACTION": "INSERT",
            "OPTION": "REPLACE",
            "ADIF": adifContent
        ]
        request.httpBody = formEncode(formData).data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse("Cannot decode response as UTF-8, \(data.count) bytes")
        }

        let parsed = Self.parseResponse(responseString)

        if parsed["RESULT"] == "AUTH" {
            throw QRZError.sessionExpired
        }

        // Accept OK, REPLACE (duplicate replaced), or PARTIAL (some succeeded)
        let result = parsed["RESULT"] ?? ""
        guard result == "OK" || result == "REPLACE" || result == "PARTIAL" else {
            // Include full response for debugging
            let reason = parsed["REASON"] ?? "Response: \(responseString.prefix(200))"
            throw QRZError.uploadFailed(reason)
        }

        let count = Int(parsed["COUNT"] ?? "0") ?? 0
        let dupes = Int(parsed["DUPES"] ?? "0") ?? 0

        return (uploaded: count, duplicates: dupes)
    }

    /// Fetch QSOs from QRZ logbook with pagination
    func fetchQSOs(since: Date? = nil) async throws -> [QRZFetchedQSO] {
        let apiKey = try getApiKey()

        var allQSOs: [QRZFetchedQSO] = []
        var offset = 0
        let pageSize = 2000  // QRZ max is 2000 per request

        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        while true {
            // Build OPTION parameter with comma-separated filters
            // Note: QRZ doesn't like OFFSET:0, so only include it when > 0
            var optionParts = ["MAX:\(pageSize)"]
            if offset > 0 {
                optionParts.append("OFFSET:\(offset)")
            }

            // Add MODSINCE filter if date provided
            if let since = since {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone(identifier: "UTC")
                optionParts.append("MODSINCE:\(formatter.string(from: since))")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            // Form-encode the body
            let formData = [
                "KEY": apiKey,
                "ACTION": "FETCH",
                "OPTION": optionParts.joined(separator: ",")
            ]
            let body = formEncode(formData)
            request.httpBody = body.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)

            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                throw QRZError.invalidResponse("HTTP \(httpResponse.statusCode), body: \(String(data: data, encoding: .utf8)?.prefix(200) ?? "nil")")
            }

            // Try UTF-8 first, then fall back to ISO Latin 1 (common for ADIF data)
            let responseString: String
            if let utf8String = String(data: data, encoding: .utf8) {
                responseString = utf8String
            } else if let latin1String = String(data: data, encoding: .isoLatin1) {
                responseString = latin1String
            } else {
                // Show first bytes for debugging
                let firstBytes = data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
                throw QRZError.invalidResponse("Cannot decode \(data.count) bytes, first bytes: \(firstBytes)")
            }

            let parsed = Self.parseResponse(responseString)

            if parsed["RESULT"] == "AUTH" {
                throw QRZError.sessionExpired
            }

            // Handle "no results" scenarios - QRZ returns FAIL when there are no QSOs
            let result = parsed["RESULT"] ?? ""
            let reason = parsed["REASON"]?.lowercased() ?? ""
            let responseCount = Int(parsed["COUNT"] ?? "") ?? 0

            // "no log entries found" or FAIL with COUNT=0 means no more results
            if reason.contains("no log entries found") || (result == "FAIL" && responseCount == 0) {
                break
            }

            guard result == "OK" else {
                // Show full response for debugging when no REASON provided
                let errorReason = parsed["REASON"] ?? "RESULT=\(result), Response: \(responseString.prefix(300))"
                throw QRZError.fetchFailed(errorReason)
            }

            guard let encodedADIF = parsed["ADIF"] else {
                break
            }

            let adif = decodeADIF(encodedADIF)
            let pageQSOs = parseADIFRecords(adif)

            allQSOs.append(contentsOf: pageQSOs)

            // Use the response COUNT to determine if there are more pages
            // If QRZ returned fewer than we asked for, we've reached the end
            if responseCount < pageSize {
                break
            }

            offset += pageSize

            // Small delay between pages to be nice to the API
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
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

            // Parse frequency (ADIF FREQ field is in MHz)
            var frequency: Double?
            if let freqStr = fields["FREQ"] ?? fields["freq"], let freq = Double(freqStr) {
                frequency = freq // MHz - keep as-is
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
            addField("freq", String(format: "%.4f", freq)) // MHz
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
        // Also clear deprecated session-based keys
        try? keychain.delete(for: KeychainHelper.Keys.qrzSessionKey)
        try? keychain.delete(for: KeychainHelper.Keys.qrzUsername)
        // Clear legacy counter keys if they exist
        try? keychain.delete(for: KeychainHelper.Keys.qrzTotalUploaded)
        try? keychain.delete(for: KeychainHelper.Keys.qrzTotalDownloaded)
        try? keychain.delete(for: KeychainHelper.Keys.qrzLastUploadDate)
        try? keychain.delete(for: KeychainHelper.Keys.qrzLastDownloadDate)
    }
}
