import Foundation

// MARK: - QRZError

enum QRZError: Error, LocalizedError {
    case invalidApiKey(String)
    case subscriptionRequired
    case sessionExpired
    case uploadFailed(String)
    case fetchFailed(String)
    case networkError(Error)
    case invalidResponse(String)
    case noQSOs

    // MARK: Internal

    var errorDescription: String? {
        switch self {
        case let .invalidApiKey(reason):
            "Invalid QRZ API key: \(reason)"
        case .subscriptionRequired:
            "QRZ XML Logbook Data subscription required. Visit shop.qrz.com to subscribe."
        case .sessionExpired:
            "QRZ session expired, please re-authenticate"
        case let .uploadFailed(reason):
            "Upload failed: \(reason)"
        case let .fetchFailed(reason):
            "Fetch failed: \(reason)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidResponse(details):
            "Invalid response from QRZ: \(details)"
        case .noQSOs:
            "No QSOs found"
        }
    }
}

// MARK: - QRZStatusResponse

/// Response from QRZ STATUS action
struct QRZStatusResponse {
    let callsign: String
    let qsoCount: Int
    let confirmedCount: Int
}

// MARK: - QRZFetchedQSO

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

// MARK: - QRZClient

actor QRZClient {
    // MARK: Internal

    // MARK: Internal (for extension access)

    let baseURL = "https://logbook.qrz.com/api"
    nonisolated let keychain = KeychainHelper.shared
    let userAgent = "FullDuplex/1.0"

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
                if pair.isEmpty {
                    continue
                }
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
            "ACTION": "STATUS",
        ]
        request.httpBody = formEncode(formData).data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse("Cannot decode response as UTF-8, \(data.count) bytes")
        }

        let parsed = Self.parseResponse(responseString)

        guard parsed["RESULT"] == "OK" else {
            // AUTH means insufficient privileges (subscription required)
            if parsed["RESULT"] == "AUTH" {
                throw QRZError.subscriptionRequired
            }
            let reason =
                parsed["REASON"]
                    ?? "RESULT=\(parsed["RESULT"] ?? "nil"), response: \(responseString.prefix(200))"
            throw QRZError.invalidApiKey(reason)
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
            "ADIF": adifContent,
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
        let pageSize = 2_000

        guard let url = URL(string: baseURL) else {
            throw QRZError.invalidResponse("Invalid URL")
        }

        while true {
            let request = buildFetchRequest(url: url, apiKey: apiKey, offset: offset, pageSize: pageSize, since: since)
            let (pageQSOs, responseCount) = try await fetchQSOPage(request: request)

            allQSOs.append(contentsOf: pageQSOs)

            if responseCount < pageSize {
                break
            }
            offset += pageSize
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        return allQSOs
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

    // MARK: Private

    private func buildFetchRequest(
        url: URL, apiKey: String, offset: Int, pageSize: Int, since: Date?
    ) -> URLRequest {
        var optionParts = ["MAX:\(pageSize)"]
        if offset > 0 {
            optionParts.append("OFFSET:\(offset)")
        }
        if let since {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            optionParts.append("MODSINCE:\(formatter.string(from: since))")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let formData = ["KEY": apiKey, "ACTION": "FETCH", "OPTION": optionParts.joined(separator: ",")]
        request.httpBody = formEncode(formData).data(using: .utf8)
        return request
    }

    private func fetchQSOPage(request: URLRequest) async throws -> ([QRZFetchedQSO], Int) {
        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let bodyPreview = String(data: data, encoding: .utf8)?.prefix(200) ?? "nil"
            throw QRZError.invalidResponse("HTTP \(httpResponse.statusCode), body: \(bodyPreview)")
        }

        let responseString = try decodeResponseData(data)
        let parsed = Self.parseResponse(responseString)

        if parsed["RESULT"] == "AUTH" {
            throw QRZError.sessionExpired
        }

        let result = parsed["RESULT"] ?? ""
        let reason = parsed["REASON"]?.lowercased() ?? ""
        let responseCount = Int(parsed["COUNT"] ?? "") ?? 0

        if reason.contains("no log entries found") || (result == "FAIL" && responseCount == 0) {
            return ([], 0)
        }

        guard result == "OK" else {
            let errorReason = parsed["REASON"] ?? "RESULT=\(result), Response: \(responseString.prefix(300))"
            throw QRZError.fetchFailed(errorReason)
        }

        guard let encodedADIF = parsed["ADIF"] else {
            return ([], 0)
        }

        let adif = decodeADIF(encodedADIF)
        return (parseADIFRecords(adif), responseCount)
    }

    private func decodeResponseData(_ data: Data) throws -> String {
        if let utf8String = String(data: data, encoding: .utf8) {
            return utf8String
        }
        if let latin1String = String(data: data, encoding: .isoLatin1) {
            return latin1String
        }
        let firstBytes = data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " ")
        throw QRZError.invalidResponse("Cannot decode \(data.count) bytes, first bytes: \(firstBytes)")
    }
}

// ADIF helper methods are in QRZClient+ADIF.swift
