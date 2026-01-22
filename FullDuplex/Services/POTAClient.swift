// POTA (Parks on the Air) ADIF export and upload functionality.
//
// Groups QSOs by UTC date and park reference, generating separate
// ADIF files suitable for upload to pota.app.

import Foundation
import SwiftData

enum POTAError: Error, LocalizedError {
    case notAuthenticated
    case uploadFailed(String)
    case fetchFailed(String)
    case invalidParkReference
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with POTA"
        case .uploadFailed(let reason):
            return "POTA upload failed: \(reason)"
        case .fetchFailed(let reason):
            return "POTA fetch failed: \(reason)"
        case .invalidParkReference:
            return "Invalid park reference format"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - POTA API Response Types

struct POTAActivationsResponse: Decodable {
    let count: Int
    let activations: [POTARemoteActivation]
}

struct POTARemoteActivation: Decodable {
    let callsign: String
    let date: String
    let reference: String
    let name: String?
    let parktypeDesc: String?
    let locationDesc: String?
    let firstQso: String?
    let lastQso: String?
    let total: Int
    let cw: Int
    let data: Int
    let phone: Int

    enum CodingKeys: String, CodingKey {
        case callsign, date, reference, name, total, cw, data, phone
        case parktypeDesc = "parktype_desc"
        case locationDesc = "location_desc"
        case firstQso = "first_qso"
        case lastQso = "last_qso"
    }
}

struct POTALogbookResponse: Decodable {
    let count: Int
    let entries: [POTARemoteQSO]
}

struct POTARemoteQSO: Decodable {
    let qsoId: Int64
    let qsoDateTime: String
    let stationCallsign: String
    let operatorCallsign: String?
    let workedCallsign: String
    let band: String?
    let mode: String?
    let rstSent: String?
    let rstRcvd: String?
    let mySig: String?
    let mySigInfo: String?
    let reference: String?
    let name: String?
    let locationDesc: String?
    let sig: String?
    let sigInfo: String?
    let p2pMatch: String?

    enum CodingKeys: String, CodingKey {
        case qsoId, band, mode, reference, name, sig
        case qsoDateTime = "qsoDateTime"
        case stationCallsign = "station_callsign"
        case operatorCallsign = "operator_callsign"
        case workedCallsign = "worked_callsign"
        case rstSent = "rst_sent"
        case rstRcvd = "rst_rcvd"
        case mySig = "my_sig"
        case mySigInfo = "my_sig_info"
        case locationDesc = "locationDesc"
        case sigInfo = "sig_info"
        case p2pMatch = "p2pMatch"
    }

    // Custom decoding to handle API inconsistencies where fields can be string or int
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        qsoId = try container.decode(Int64.self, forKey: .qsoId)
        qsoDateTime = try container.decode(String.self, forKey: .qsoDateTime)
        stationCallsign = try container.decode(String.self, forKey: .stationCallsign)
        operatorCallsign = try container.decodeIfPresent(String.self, forKey: .operatorCallsign)
        workedCallsign = try container.decode(String.self, forKey: .workedCallsign)
        band = try container.decodeIfPresent(String.self, forKey: .band)
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        mySig = try container.decodeIfPresent(String.self, forKey: .mySig)
        mySigInfo = try container.decodeIfPresent(String.self, forKey: .mySigInfo)
        reference = try container.decodeIfPresent(String.self, forKey: .reference)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        locationDesc = try container.decodeIfPresent(String.self, forKey: .locationDesc)
        sig = try container.decodeIfPresent(String.self, forKey: .sig)

        // These fields can be either string or int from the POTA API
        rstSent = Self.decodeStringOrInt(container: container, key: .rstSent)
        rstRcvd = Self.decodeStringOrInt(container: container, key: .rstRcvd)
        sigInfo = Self.decodeStringOrInt(container: container, key: .sigInfo)
        p2pMatch = Self.decodeStringOrInt(container: container, key: .p2pMatch)
    }

    /// Decode a field that can be either a String or an Int from the API
    private static func decodeStringOrInt(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
        // Try string first
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return value
        }
        // Try int and convert to string
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        return nil
    }
}

/// A fetched QSO from POTA ready for import
struct POTAFetchedQSO {
    let callsign: String
    let band: String
    let mode: String
    let timestamp: Date
    let rstSent: String?
    let rstReceived: String?
    let myCallsign: String
    let parkReference: String?
    let myState: String?
    let potaQsoId: Int64
}

struct POTAUploadResult {
    let success: Bool
    let qsosAccepted: Int
    let message: String?
}

actor POTAClient {
    private let baseURL = "https://api.pota.app"
    private let authService: POTAAuthService

    init(authService: POTAAuthService) {
        self.authService = authService
    }

    func uploadActivation(parkReference: String, qsos: [QSO]) async throws -> POTAUploadResult {
        let debugLog = await SyncDebugLog.shared

        // Validate park reference format (e.g., "K-1234", "VE-1234", "US-1234")
        // Format: 1-4 letters, hyphen, 1-6 digits (case-insensitive)
        let parkPattern = #"^[A-Za-z]{1,4}-\d{1,6}$"#
        guard parkReference.range(of: parkPattern, options: .regularExpression) != nil else {
            await debugLog.error("Invalid park reference format: '\(parkReference)' (expected format like K-1234)", service: .pota)
            throw POTAError.invalidParkReference
        }

        // Normalize to uppercase for API
        let normalizedParkRef = parkReference.uppercased()

        // Get valid token
        let token = try await authService.ensureValidToken()

        // Filter QSOs for this park (case-insensitive match)
        let parkQSOs = qsos.filter { $0.parkReference?.uppercased() == normalizedParkRef }
        guard !parkQSOs.isEmpty else {
            await debugLog.info("No QSOs to upload for park \(normalizedParkRef)", service: .pota)
            return POTAUploadResult(success: true, qsosAccepted: 0, message: "No QSOs for this park")
        }

        await debugLog.info("Uploading \(parkQSOs.count) QSOs to park \(normalizedParkRef)", service: .pota)

        // Extract callsign from first QSO
        let callsign = parkQSOs.first?.myCallsign ?? "UNKNOWN"

        // Compute location from park reference prefix + state (derived from grid)
        // Park reference format: XX-NNNN (e.g., "US-4571")
        // Location format: XX-SS (e.g., "US-CA")
        let parkPrefix = normalizedParkRef.split(separator: "-").first.map(String.init) ?? "US"
        let myGrid = parkQSOs.first?.myGrid
        let derivedState = myGrid.flatMap { Self.gridToUSState($0) }
        let location: String
        if parkPrefix == "US" || parkPrefix == "K", let state = derivedState {
            location = "US-\(state)"
        } else {
            location = parkPrefix
        }

        // Generate ADIF content
        let adifContent = generateADIF(for: parkQSOs, parkReference: normalizedParkRef)

        // Generate filename in POTA convention: {callsign}@{park}-{YYMMDD}.adi
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = parkQSOs.first.map { dateFormatter.string(from: $0.timestamp) } ?? "000000"
        let filename = "\(callsign)@\(normalizedParkRef)-\(dateStr).adi"

        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add ADIF file first (field name must be "adif")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"adif\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(adifContent.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        // Add required text fields
        for (name, value) in [("reference", normalizedParkRef), ("location", location), ("callsign", callsign)] {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request (endpoint is /adif, not /activation)
        guard let url = URL(string: "\(baseURL)/adif") else {
            await debugLog.error("Invalid URL for POTA upload", service: .pota)
            throw POTAError.uploadFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        await debugLog.debug("POST /adif - callsign=\(callsign), location=\(location), reference=\(normalizedParkRef), filename=\(filename)", service: .pota)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            await debugLog.error("Invalid response (not HTTP)", service: .pota)
            throw POTAError.uploadFailed("Invalid response")
        }

        let responseBody = String(data: data, encoding: .utf8) ?? "(binary data)"
        await debugLog.debug("Response \(httpResponse.statusCode): \(responseBody.prefix(500))", service: .pota)

        switch httpResponse.statusCode {
        case 200...299:
            // Parse success response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let count = json["qsosAccepted"] as? Int ?? parkQSOs.count
                let message = json["message"] as? String
                await debugLog.info("Upload success: \(count) QSOs accepted for \(normalizedParkRef)", service: .pota)
                return POTAUploadResult(success: true, qsosAccepted: count, message: message)
            }
            await debugLog.info("Upload success: \(parkQSOs.count) QSOs for \(normalizedParkRef) (no count in response)", service: .pota)
            return POTAUploadResult(success: true, qsosAccepted: parkQSOs.count, message: nil)

        case 401:
            await debugLog.error("Upload failed: 401 Unauthorized - token may be expired", service: .pota)
            throw POTAError.notAuthenticated

        case 400...499:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Client error"
            await debugLog.error("Upload failed: \(httpResponse.statusCode) - \(errorMessage)", service: .pota)
            throw POTAError.uploadFailed(errorMessage)

        default:
            await debugLog.error("Upload failed: \(httpResponse.statusCode) - Server error", service: .pota)
            throw POTAError.uploadFailed("Server error: \(httpResponse.statusCode)")
        }
    }

    /// Upload activation with attempt recording for debugging
    func uploadActivationWithRecording(
        parkReference: String,
        qsos: [QSO],
        modelContext: ModelContext
    ) async throws -> POTAUploadResult {
        let debugLog = await SyncDebugLog.shared
        let startTime = Date()

        // Validate park reference format
        let parkPattern = #"^[A-Za-z]{1,4}-\d{1,6}$"#
        guard parkReference.range(of: parkPattern, options: .regularExpression) != nil else {
            await debugLog.error("Invalid park reference format: '\(parkReference)' (expected format like K-1234)", service: .pota)
            throw POTAError.invalidParkReference
        }

        let normalizedParkRef = parkReference.uppercased()

        // Get token (don't record attempt yet in case auth fails)
        let token = try await authService.ensureValidToken()

        // Filter QSOs for this park
        let parkQSOs = qsos.filter { $0.parkReference?.uppercased() == normalizedParkRef }
        guard !parkQSOs.isEmpty else {
            await debugLog.info("No QSOs to upload for park \(normalizedParkRef)", service: .pota)
            return POTAUploadResult(success: true, qsosAccepted: 0, message: "No QSOs for this park")
        }

        await debugLog.info("Uploading \(parkQSOs.count) QSOs to park \(normalizedParkRef)", service: .pota)

        let callsign = parkQSOs.first?.myCallsign ?? "UNKNOWN"
        let parkPrefix = normalizedParkRef.split(separator: "-").first.map(String.init) ?? "US"
        let myGrid = parkQSOs.first?.myGrid
        let derivedState = myGrid.flatMap { Self.gridToUSState($0) }
        let location: String
        if parkPrefix == "US" || parkPrefix == "K", let state = derivedState {
            location = "US-\(state)"
        } else {
            location = parkPrefix
        }

        let adifContent = generateADIF(for: parkQSOs, parkReference: normalizedParkRef)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyMMdd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateStr = parkQSOs.first.map { dateFormatter.string(from: $0.timestamp) } ?? "000000"
        let filename = "\(callsign)@\(normalizedParkRef)-\(dateStr).adi"

        // Build request
        let boundary = UUID().uuidString
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"adif\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(adifContent.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)

        for (name, value) in [("reference", normalizedParkRef), ("location", location), ("callsign", callsign)] {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        guard let url = URL(string: "\(baseURL)/adif") else {
            await debugLog.error("Invalid URL for POTA upload", service: .pota)
            throw POTAError.uploadFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Capture headers for recording (redact auth token)
        let recordedHeaders = [
            "Content-Type": "multipart/form-data; boundary=\(boundary)",
            "Authorization": "[REDACTED]"
        ]

        // Create upload attempt record
        let attempt = await MainActor.run {
            let attempt = POTAUploadAttempt(
                timestamp: startTime,
                parkReference: normalizedParkRef,
                qsoCount: parkQSOs.count,
                callsign: callsign,
                location: location,
                adifContent: adifContent,
                requestHeaders: recordedHeaders,
                filename: filename
            )
            modelContext.insert(attempt)
            return attempt
        }

        await debugLog.debug("POST /adif - callsign=\(callsign), location=\(location), reference=\(normalizedParkRef), filename=\(filename)", service: .pota)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await MainActor.run {
                    attempt.markFailed(httpStatusCode: nil, responseBody: nil, errorMessage: "Invalid response (not HTTP)", durationMs: durationMs)
                }
                await debugLog.error("Invalid response (not HTTP)", service: .pota)
                throw POTAError.uploadFailed("Invalid response")
            }

            let responseBody = String(data: data, encoding: .utf8) ?? "(binary data)"
            await debugLog.debug("Response \(httpResponse.statusCode): \(responseBody.prefix(500))", service: .pota)

            switch httpResponse.statusCode {
            case 200...299:
                await MainActor.run {
                    attempt.markCompleted(httpStatusCode: httpResponse.statusCode, responseBody: responseBody, durationMs: durationMs)
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let count = json["qsosAccepted"] as? Int ?? parkQSOs.count
                    let message = json["message"] as? String
                    await debugLog.info("Upload success: \(count) QSOs accepted for \(normalizedParkRef)", service: .pota)
                    return POTAUploadResult(success: true, qsosAccepted: count, message: message)
                }
                await debugLog.info("Upload success: \(parkQSOs.count) QSOs for \(normalizedParkRef) (no count in response)", service: .pota)
                return POTAUploadResult(success: true, qsosAccepted: parkQSOs.count, message: nil)

            case 401:
                await MainActor.run {
                    attempt.markFailed(httpStatusCode: httpResponse.statusCode, responseBody: responseBody, errorMessage: "Unauthorized - token may be expired", durationMs: durationMs)
                }
                await debugLog.error("Upload failed: 401 Unauthorized - token may be expired", service: .pota)
                throw POTAError.notAuthenticated

            case 400...499:
                let errorMessage = String(data: data, encoding: .utf8) ?? "Client error"
                await MainActor.run {
                    attempt.markFailed(httpStatusCode: httpResponse.statusCode, responseBody: responseBody, errorMessage: errorMessage, durationMs: durationMs)
                }
                await debugLog.error("Upload failed: \(httpResponse.statusCode) - \(errorMessage)", service: .pota)
                throw POTAError.uploadFailed(errorMessage)

            default:
                await MainActor.run {
                    attempt.markFailed(httpStatusCode: httpResponse.statusCode, responseBody: responseBody, errorMessage: "Server error: \(httpResponse.statusCode)", durationMs: durationMs)
                }
                await debugLog.error("Upload failed: \(httpResponse.statusCode) - Server error", service: .pota)
                throw POTAError.uploadFailed("Server error: \(httpResponse.statusCode)")
            }
        } catch let error as POTAError {
            throw error
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            await MainActor.run {
                attempt.markFailed(httpStatusCode: nil, responseBody: nil, errorMessage: error.localizedDescription, durationMs: durationMs)
            }
            throw POTAError.networkError(error)
        }
    }

    private func generateADIF(for qsos: [QSO], parkReference: String) -> String {
        var lines: [String] = []

        // Header
        lines.append("ADIF Export for POTA")
        lines.append("<adif_ver:5>3.1.4")
        lines.append("<programid:10>FullDuplex")
        lines.append("<eoh>")
        lines.append("")

        // Records
        for qso in qsos {
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
            addField("my_sig", "POTA")
            addField("my_sig_info", parkReference)
            addField("comment", qso.notes)

            lines.append(fields.joined(separator: " ") + " <eor>")
        }

        return lines.joined(separator: "\n")
    }

    /// Get all unique park references from QSOs (excludes nil and empty)
    static func groupQSOsByPark(_ qsos: [QSO]) -> [String: [QSO]] {
        Dictionary(grouping: qsos.filter { $0.parkReference?.isEmpty == false }) { $0.parkReference! }
    }

    /// Derive US state from Maidenhead grid square (4 or 6 character)
    /// Returns the most likely state abbreviation for US grid squares.
    /// This is approximate - grid squares can span state boundaries.
    static func gridToUSState(_ grid: String) -> String? {
        guard grid.count >= 4 else { return nil }

        let field = grid.prefix(2).uppercased()
        let square = String(grid.dropFirst(2).prefix(2))

        // Map field + square to most likely US state
        switch (field, square) {
        // California
        case ("CM", "87"), ("CM", "88"), ("CM", "97"), ("CM", "98"):
            return "CA"
        case ("DM", "03"), ("DM", "04"), ("DM", "05"), ("DM", "06"), ("DM", "07"),
             ("DM", "12"), ("DM", "13"), ("DM", "14"):
            return "CA"
        // Arizona
        case ("DM", "31"), ("DM", "32"), ("DM", "33"), ("DM", "41"), ("DM", "42"), ("DM", "43"):
            return "AZ"
        // Nevada
        case ("DM", "08"), ("DM", "09"), ("DM", "18"), ("DM", "19"), ("DM", "26"), ("DM", "27"):
            return "NV"
        // Washington
        case ("CN", "74"), ("CN", "75"), ("CN", "84"), ("CN", "85"), ("CN", "86"), ("CN", "87"), ("CN", "88"):
            return "WA"
        // Oregon
        case ("CN", "73"), ("CN", "82"), ("CN", "83"), ("CN", "93"), ("CN", "94"), ("CN", "95"):
            return "OR"
        // Texas
        case ("EM", "00"), ("EM", "01"), ("EM", "10"), ("EM", "11"), ("EM", "12"), ("EM", "13"),
             ("EM", "20"), ("EM", "21"):
            return "TX"
        // Florida
        case ("EL", "87"), ("EL", "88"), ("EL", "96"), ("EL", "97"), ("EL", "98"):
            return "FL"
        // New York
        case ("FN", "21"), ("FN", "30"), ("FN", "31"), ("FN", "10"), ("FN", "11"), ("FN", "20"):
            return "NY"
        // Colorado
        case ("DM", "69"), ("DM", "79"), ("DM", "78"), ("DN", "60"), ("DN", "70"):
            return "CO"
        default:
            // Fall back to field-level approximation
            switch field {
            case "CM", "DM": return "CA"
            case "CN": return "WA"
            case "DN": return "CO"
            case "EM": return "TX"
            case "EN": return "WI"
            case "EL": return "FL"
            case "FM": return "VA"
            case "FN": return "NY"
            default: return nil
            }
        }
    }

    // MARK: - Download Methods

    /// Fetch all activations from POTA
    func fetchActivations() async throws -> [POTARemoteActivation] {
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/activations?all=1") else {
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let decoded = try JSONDecoder().decode(POTAActivationsResponse.self, from: data)
        return decoded.activations
    }

    /// Fetch QSOs for a specific activation
    func fetchActivationQSOs(reference: String, date: String, page: Int = 1, pageSize: Int = 100) async throws -> POTALogbookResponse {
        let token = try await authService.ensureValidToken()

        var components = URLComponents(string: "\(baseURL)/user/logbook")!
        components.queryItems = [
            URLQueryItem(name: "activatorOnly", value: "1"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "size", value: String(pageSize)),
            URLQueryItem(name: "startDate", value: date),
            URLQueryItem(name: "endDate", value: date),
            URLQueryItem(name: "reference", value: reference)
        ]

        guard let url = components.url else {
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.fetchFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode(POTALogbookResponse.self, from: data)
    }

    /// Fetch all QSOs for an activation (handles pagination)
    func fetchAllActivationQSOs(reference: String, date: String) async throws -> [POTARemoteQSO] {
        var allQSOs: [POTARemoteQSO] = []
        var page = 1
        let pageSize = 100

        while true {
            let response = try await fetchActivationQSOs(reference: reference, date: date, page: page, pageSize: pageSize)
            allQSOs.append(contentsOf: response.entries)

            // If we got fewer than pageSize, we're done
            if response.entries.count < pageSize {
                break
            }

            // Safety limit
            if page >= 10 {
                break
            }

            page += 1
        }

        return allQSOs
    }

    /// Fetch all QSOs from all activations
    func fetchAllQSOs() async throws -> [POTAFetchedQSO] {
        let activations = try await fetchActivations()
        var allFetched: [POTAFetchedQSO] = []

        for activation in activations {
            let qsos = try await fetchAllActivationQSOs(reference: activation.reference, date: activation.date)

            for qso in qsos {
                if let fetched = convertToFetchedQSO(qso, activation: activation) {
                    allFetched.append(fetched)
                }
            }

            // Small delay between activations to be nice to the API
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        return allFetched
    }

    // MARK: - Job Status Methods

    /// Fetch upload job statuses from POTA API
    func fetchJobs() async throws -> [POTAJob] {
        let debugLog = await SyncDebugLog.shared
        let token = try await authService.ensureValidToken()

        guard let url = URL(string: "\(baseURL)/user/jobs") else {
            await debugLog.error("Invalid URL for POTA jobs", service: .pota)
            throw POTAError.fetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Authorization")

        await debugLog.debug("GET /user/jobs", service: .pota)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            await debugLog.error("Invalid response (not HTTP)", service: .pota)
            throw POTAError.fetchFailed("Invalid response")
        }

        await debugLog.debug("Jobs response: \(httpResponse.statusCode)", service: .pota)

        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode == 401 {
                throw POTAError.notAuthenticated
            }
            let body = String(data: data, encoding: .utf8) ?? ""
            await debugLog.error("Jobs fetch failed: \(httpResponse.statusCode) - \(body)", service: .pota)
            throw POTAError.fetchFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        let jobs = try JSONDecoder().decode([POTAJob].self, from: data)
        await debugLog.info("Fetched \(jobs.count) POTA jobs", service: .pota)
        return jobs
    }

    /// Convert a POTA API QSO to our fetched format
    private func convertToFetchedQSO(_ qso: POTARemoteQSO, activation: POTARemoteActivation) -> POTAFetchedQSO? {
        guard let band = qso.band, let mode = qso.mode else {
            return nil
        }

        // Parse datetime: "2025-01-15T14:30:00" -> Date
        // POTA API returns datetime without timezone suffix, so use DateFormatter
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let timestamp = formatter.date(from: qso.qsoDateTime) ?? Date()

        // Extract state from locationDesc (e.g., "US-CA" -> "CA")
        let myState = activation.locationDesc?.split(separator: "-").last.map(String.init)

        return POTAFetchedQSO(
            callsign: qso.workedCallsign,
            band: band,
            mode: mode,
            timestamp: timestamp,
            rstSent: qso.rstSent,
            rstReceived: qso.rstRcvd,
            myCallsign: qso.stationCallsign,
            parkReference: activation.reference,
            myState: myState,
            potaQsoId: qso.qsoId
        )
    }
}
