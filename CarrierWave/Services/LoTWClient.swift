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

@MainActor
final class LoTWClient {
    // MARK: Internal

    let keychain = KeychainHelper.shared

    let baseURL = "https://lotw.arrl.org/lotwuser/lotwreport.adi"
    let userAgent = "CarrierWave/1.0"

    // MARK: - Configuration

    var isConfigured: Bool {
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

    /// Fetch QSOs with adaptive date windowing to handle rate limits
    /// If a request fails with rate limit, progressively shrinks the date window
    func fetchQSOs(qsoRxSince: Date? = nil) async throws -> LoTWResponse {
        let credentials = try getCredentials()

        // Use provided date or default to 2000-01-01 for first sync
        let startDate =
            qsoRxSince ?? DateComponents(
                calendar: Calendar(identifier: .gregorian),
                year: 2_000, month: 1, day: 1
            ).date!

        let endDate = Date()

        // If date range is small (< 30 days), just do a single request
        let daysBetween = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        if daysBetween <= 30 {
            return try await fetchQSOsForDateRange(
                credentials: credentials, startDate: startDate, endDate: nil
            )
        }

        // For larger ranges, use adaptive windowing
        return try await fetchQSOsWithAdaptiveWindowing(
            credentials: credentials, startDate: startDate, endDate: endDate
        )
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

    /// Fetch QSOs for a specific date range
    func fetchQSOsForDateRange(
        credentials: (username: String, password: String),
        startDate: Date,
        endDate: Date?
    ) async throws -> LoTWResponse {
        var components = URLComponents(string: baseURL)!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "login", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password),
            URLQueryItem(name: "qso_query", value: "1"),
            URLQueryItem(name: "qso_qsl", value: "no"),
            URLQueryItem(name: "qso_qsorxsince", value: dateFormatter.string(from: startDate)),
            URLQueryItem(name: "qso_mydetail", value: "yes"),
            URLQueryItem(name: "qso_qsldetail", value: "yes"),
            URLQueryItem(name: "qso_withown", value: "yes"),
        ]

        // Add end date filter if specified (for windowed requests)
        if let endDate {
            // LoTW uses qso_enddate for the QSO date, not upload date
            // We'll filter by upload date range using qso_qsorxsince already
            // For windowing, we track progress by startDate advancement
            queryItems.append(URLQueryItem(name: "qso_enddate", value: dateFormatter.string(from: endDate)))
        }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw LoTWError.invalidResponse("Cannot decode response as UTF-8")
        }

        // Check for EOH tag to verify success
        guard responseString.contains("<EOH>") || responseString.contains("<eoh>") else {
            if isAuthenticationError(responseString) {
                throw LoTWError.authenticationFailed
            }
            throw LoTWError.serviceError(String(responseString.prefix(200)))
        }

        return parseADIFResponse(responseString)
    }

    /// Check if error message indicates rate limiting
    func isRateLimitError(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("page request limit")
            || lowercased.contains("rate limit")
            || lowercased.contains("too many requests")
            || lowercased.contains("503")
            || lowercased.contains("error 503")
    }

    /// Format date for logging
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    // MARK: Private

    private func isAuthenticationError(_ response: String) -> Bool {
        let lowercased = response.lowercased()
        return lowercased.contains("password incorrect")
            || lowercased.contains("username not found")
    }
}
