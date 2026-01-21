import Foundation

enum QRZError: Error, LocalizedError {
    case invalidCredentials
    case sessionExpired
    case uploadFailed(String)
    case networkError(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid QRZ username or password"
        case .sessionExpired:
            return "QRZ session expired, please re-authenticate"
        case .uploadFailed(let reason):
            return "Upload failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from QRZ"
        }
    }
}

actor QRZClient {
    private let baseURL = "https://logbook.qrz.com/api"
    private let keychain = KeychainHelper.shared

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

    func authenticate(username: String, password: String) async throws -> String {
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "ACTION", value: "LOGIN"),
            URLQueryItem(name: "USERNAME", value: username),
            URLQueryItem(name: "PASSWORD", value: password)
        ]

        guard let url = components.url else {
            throw QRZError.invalidResponse
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw QRZError.invalidResponse
        }

        let parsed = Self.parseResponse(responseString)

        guard parsed["RESULT"] == "OK", let key = parsed["KEY"] else {
            throw QRZError.invalidCredentials
        }

        // Store credentials
        try keychain.save(key, for: KeychainHelper.Keys.qrzSessionKey)
        try keychain.save(username, for: KeychainHelper.Keys.qrzUsername)

        return key
    }

    func getSessionKey() throws -> String {
        try keychain.readString(for: KeychainHelper.Keys.qrzSessionKey)
    }

    func uploadQSOs(_ qsos: [QSO]) async throws -> (uploaded: Int, duplicates: Int) {
        let sessionKey = try getSessionKey()

        // Convert QSOs to ADIF
        let adifContent = qsos.map { qso in
            qso.rawADIF ?? generateADIF(for: qso)
        }.joined(separator: "\n")

        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "ACTION", value: "INSERT"),
            URLQueryItem(name: "KEY", value: sessionKey),
            URLQueryItem(name: "ADIF", value: adifContent)
        ]

        guard let url = components.url else {
            throw QRZError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

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

        return (uploaded: count, duplicates: dupes)
    }

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

    func logout() {
        try? keychain.delete(for: KeychainHelper.Keys.qrzSessionKey)
    }
}
