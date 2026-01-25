import Foundation

// MARK: - LoTWResponse

struct LoTWResponse {
    let qsos: [LoTWFetchedQSO]
    let lastQSL: Date?
    let lastQSORx: Date?
    let recordCount: Int
}

// MARK: - LoTWFetchedQSO

struct LoTWFetchedQSO {
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
    let state: String?
    let country: String?
    let dxcc: Int?
    let qslReceived: Bool
    let qslReceivedDate: Date?
    let rawADIF: String
}

// MARK: - LoTWClient

actor LoTWClient {
    // MARK: Internal

    nonisolated let keychain = KeychainHelper.shared

    // MARK: - Configuration

    nonisolated var isConfigured: Bool {
        (try? keychain.readString(for: KeychainHelper.Keys.lotwUsername)) != nil
            && (try? keychain.readString(for: KeychainHelper.Keys.lotwPassword)) != nil
    }

    // MARK: - Credential Management

    func saveCredentials(username: String, password: String) throws {
        try keychain.save(username, for: KeychainHelper.Keys.lotwUsername)
        try keychain.save(password, for: KeychainHelper.Keys.lotwPassword)
    }

    func getCredentials() throws -> (username: String, password: String) {
        let username = try keychain.readString(for: KeychainHelper.Keys.lotwUsername)
        let password = try keychain.readString(for: KeychainHelper.Keys.lotwPassword)
        return (username, password)
    }

    func hasCredentials() -> Bool {
        do {
            _ = try getCredentials()
            return true
        } catch {
            return false
        }
    }

    func clearCredentials() {
        try? keychain.delete(for: KeychainHelper.Keys.lotwUsername)
        try? keychain.delete(for: KeychainHelper.Keys.lotwPassword)
        try? keychain.delete(for: KeychainHelper.Keys.lotwLastQSL)
        try? keychain.delete(for: KeychainHelper.Keys.lotwLastQSORx)
    }

    // MARK: - Sync Timestamps

    func getLastQSORxDate() -> Date? {
        guard let dateString = try? keychain.readString(for: KeychainHelper.Keys.lotwLastQSORx)
        else {
            return nil
        }
        return ISO8601DateFormatter().date(from: dateString)
    }

    func saveLastQSORxDate(_ date: Date) throws {
        let dateString = ISO8601DateFormatter().string(from: date)
        try keychain.save(dateString, for: KeychainHelper.Keys.lotwLastQSORx)
    }

    // MARK: - API Methods

    func fetchQSOs(qsoRxSince: Date? = nil) async throws -> LoTWResponse {
        let credentials = try getCredentials()

        var components = URLComponents(string: baseURL)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        // Use provided date or default to 2000-01-01 for first sync to get all QSOs
        let rxSinceDate =
            qsoRxSince ?? DateComponents(
                calendar: Calendar(identifier: .gregorian),
                year: 2_000, month: 1, day: 1
            ).date!

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "login", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
            URLQueryItem(name: "qso_query", value: "1"),
            URLQueryItem(name: "qso_qsl", value: "no"), // Fetch all QSOs, not just confirmed QSLs
            URLQueryItem(name: "qso_qsorxsince", value: dateFormatter.string(from: rxSinceDate)),
            URLQueryItem(name: "qso_mydetail", value: "yes"),
            URLQueryItem(name: "qso_qsldetail", value: "yes"),
            URLQueryItem(name: "qso_withown", value: "yes"),
        ]

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw LoTWError.invalidResponse("Cannot decode response as UTF-8")
        }

        // Check for EOH tag to verify success
        guard responseString.contains("<EOH>") || responseString.contains("<eoh>") else {
            // Check for common error patterns
            if isAuthenticationError(responseString) {
                throw LoTWError.authenticationFailed
            }
            throw LoTWError.serviceError(String(responseString.prefix(200)))
        }

        return parseADIFResponse(responseString)
    }

    /// Test credentials by fetching recent QSLs only
    func testCredentials(username: String, password: String) async throws {
        var components = URLComponents(string: baseURL)!

        // Use a recent date to minimize data transfer
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let recentDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

        components.queryItems = [
            URLQueryItem(name: "login", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "qso_query", value: "1"),
            URLQueryItem(name: "qso_qsl", value: "yes"),
            URLQueryItem(name: "qso_qslsince", value: dateFormatter.string(from: recentDate)),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw LoTWError.invalidResponse("Cannot decode response as UTF-8")
        }

        guard responseString.contains("<EOH>") || responseString.contains("<eoh>") else {
            if isAuthenticationError(responseString) {
                throw LoTWError.authenticationFailed
            }
            throw LoTWError.serviceError(String(responseString.prefix(200)))
        }
    }

    // MARK: Private

    private let baseURL = "https://lotw.arrl.org/lotwuser/lotwreport.adi"
    private let userAgent = "CarrierWave/1.0"

    private func isAuthenticationError(_ response: String) -> Bool {
        let lowercased = response.lowercased()
        return lowercased.contains("password incorrect")
            || lowercased.contains("username not found")
    }

    // MARK: - ADIF Parsing

    private func parseADIFResponse(_ adif: String) -> LoTWResponse {
        var qsos: [LoTWFetchedQSO] = []
        var lastQSL: Date?
        var lastQSORx: Date?
        var recordCount = 0

        // Parse header for metadata
        if let headerEnd = adif.range(of: "<EOH>", options: .caseInsensitive) {
            let header = String(adif[..<headerEnd.lowerBound])
            lastQSL = parseHeaderDate(header, field: "APP_LoTW_LASTQSL")
            lastQSORx = parseHeaderDate(header, field: "APP_LoTW_LASTQSORX")
            if let count = parseHeaderField(header, field: "APP_LoTW_NUMREC") {
                recordCount = Int(count) ?? 0
            }
        }

        // Split into records (case-insensitive - LoTW uses lowercase <eor>)
        let records = adif.components(separatedBy: "<eor>")
            .flatMap { $0.components(separatedBy: "<EOR>") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.contains("<") }

        for record in records {
            // Skip header
            if record.uppercased().contains("<EOH>") {
                continue
            }

            if let qso = parseQSORecord(record) {
                qsos.append(qso)
            }
        }

        return LoTWResponse(
            qsos: qsos,
            lastQSL: lastQSL,
            lastQSORx: lastQSORx,
            recordCount: recordCount
        )
    }

    private func parseHeaderField(_ header: String, field: String) -> String? {
        let pattern = "<\(field):([0-9]+)>([^<]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: header, range: NSRange(header.startIndex..., in: header)
              ),
              let valueRange = Range(match.range(at: 2), in: header)
        else {
            return nil
        }
        return String(header[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseHeaderDate(_ header: String, field: String) -> Date? {
        guard let value = parseHeaderField(header, field: field) else {
            return nil
        }
        // Format: YYYY-MM-DD HH:MM:SS
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: value)
    }

    private func extractField(_ name: String, from record: String) -> String? {
        let pattern = "<\(name):([0-9]+)>([^<]*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: record, range: NSRange(record.startIndex..., in: record)
              ),
              let valueRange = Range(match.range(at: 2), in: record)
        else {
            return nil
        }
        let value = String(record[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func parseQSOTimestamp(dateStr: String, timeStr: String?) -> Date? {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMddHHmm"
        let timeOnStr = timeStr ?? "0000"
        let dateTimeStr = dateStr + timeOnStr.prefix(4)
        return dateFormatter.date(from: dateTimeStr)
    }

    private func parseQSLReceivedDate(_ record: String) -> Date? {
        guard let qslDateStr = extractField("QSLRDATE", from: record) else {
            return nil
        }
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        dateFormatter.dateFormat = "yyyyMMdd"
        return dateFormatter.date(from: qslDateStr)
    }

    private func parseQSORecord(_ record: String) -> LoTWFetchedQSO? {
        guard let callsign = extractField("CALL", from: record),
              let band = extractField("BAND", from: record),
              let mode = extractField("MODE", from: record),
              let qsoDateStr = extractField("QSO_DATE", from: record),
              let timestamp = parseQSOTimestamp(
                  dateStr: qsoDateStr, timeStr: extractField("TIME_ON", from: record)
              )
        else {
            return nil
        }

        let qslReceived = extractField("QSL_RCVD", from: record)?.uppercased() == "Y"

        return LoTWFetchedQSO(
            callsign: callsign,
            band: band,
            mode: mode,
            frequency: extractField("FREQ", from: record).flatMap { Double($0) },
            timestamp: timestamp,
            rstSent: extractField("RST_SENT", from: record),
            rstReceived: extractField("RST_RCVD", from: record),
            myCallsign: extractField("STATION_CALLSIGN", from: record)
                ?? extractField("APP_LoTW_OWNCALL", from: record),
            myGrid: extractField("MY_GRIDSQUARE", from: record),
            theirGrid: extractField("GRIDSQUARE", from: record),
            state: extractField("STATE", from: record),
            country: extractField("COUNTRY", from: record),
            dxcc: extractField("DXCC", from: record).flatMap { Int($0) },
            qslReceived: qslReceived,
            qslReceivedDate: parseQSLReceivedDate(record),
            rawADIF: record
        )
    }
}
