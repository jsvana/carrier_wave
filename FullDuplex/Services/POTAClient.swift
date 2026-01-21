import Foundation

enum POTAError: Error, LocalizedError {
    case notAuthenticated
    case uploadFailed(String)
    case invalidParkReference
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with POTA"
        case .uploadFailed(let reason):
            return "POTA upload failed: \(reason)"
        case .invalidParkReference:
            return "Invalid park reference format"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
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
        // Validate park reference format (e.g., "K-1234", "VE-1234")
        let parkPattern = #"^[A-Z]{1,2}-\d{4,5}$"#
        guard parkReference.range(of: parkPattern, options: .regularExpression) != nil else {
            throw POTAError.invalidParkReference
        }

        // Get valid token
        let token = try await authService.ensureValidToken()

        // Filter QSOs for this park
        let parkQSOs = qsos.filter { $0.parkReference == parkReference }
        guard !parkQSOs.isEmpty else {
            return POTAUploadResult(success: true, qsosAccepted: 0, message: "No QSOs for this park")
        }

        // Generate ADIF content
        let adifContent = generateADIF(for: parkQSOs, parkReference: parkReference)

        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add ADIF file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"activation.adi\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(adifContent.data(using: .utf8)!)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request
        guard let url = URL(string: "\(baseURL)/activation") else {
            throw POTAError.uploadFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw POTAError.uploadFailed("Invalid response")
        }

        switch httpResponse.statusCode {
        case 200...299:
            // Parse success response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let count = json["qsosAccepted"] as? Int ?? parkQSOs.count
                let message = json["message"] as? String
                return POTAUploadResult(success: true, qsosAccepted: count, message: message)
            }
            return POTAUploadResult(success: true, qsosAccepted: parkQSOs.count, message: nil)

        case 401:
            throw POTAError.notAuthenticated

        case 400...499:
            let errorMessage = String(data: data, encoding: .utf8) ?? "Client error"
            throw POTAError.uploadFailed(errorMessage)

        default:
            throw POTAError.uploadFailed("Server error: \(httpResponse.statusCode)")
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
                addField("freq", String(format: "%.4f", freq / 1000))
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

    /// Get all unique park references from QSOs
    static func groupQSOsByPark(_ qsos: [QSO]) -> [String: [QSO]] {
        Dictionary(grouping: qsos.filter { $0.parkReference != nil }) { $0.parkReference! }
    }
}
