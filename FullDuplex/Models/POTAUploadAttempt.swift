// POTA upload attempt tracking model
//
// SwiftData model that records each upload attempt with full request/response
// details for debugging and correlation with POTA job status.

import Foundation
import SwiftData

@Model
class POTAUploadAttempt {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var parkReference: String = ""
    var qsoCount: Int = 0
    var callsign: String = ""
    var location: String = ""

    // Request details
    var adifContent: String = ""
    // Store headers as JSON string to avoid ValueTransformer issues
    var requestHeadersJSON: String = "{}"
    var filename: String = ""

    // Response details
    var httpStatusCode: Int?
    var responseBody: String?
    var errorMessage: String?
    var success: Bool = false

    // Timing
    var requestDurationMs: Int?

    // Correlation
    var correlatedJobId: Int?

    /// Computed property for accessing headers as dictionary
    var requestHeaders: [String: String] {
        get {
            guard let data = requestHeadersJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                requestHeadersJSON = json
            } else {
                requestHeadersJSON = "{}"
            }
        }
    }

    init(
        timestamp: Date = Date(),
        parkReference: String,
        qsoCount: Int,
        callsign: String,
        location: String,
        adifContent: String,
        requestHeaders: [String: String],
        filename: String
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.parkReference = parkReference
        self.qsoCount = qsoCount
        self.callsign = callsign
        self.location = location
        self.adifContent = adifContent
        self.filename = filename
        // Set headers via JSON encoding
        if let data = try? JSONEncoder().encode(requestHeaders),
           let json = String(data: data, encoding: .utf8) {
            self.requestHeadersJSON = json
        }
    }

    func markCompleted(httpStatusCode: Int, responseBody: String?, durationMs: Int) {
        self.httpStatusCode = httpStatusCode
        self.responseBody = responseBody
        self.requestDurationMs = durationMs
        self.success = (200...299).contains(httpStatusCode)
        self.errorMessage = nil
    }

    func markFailed(httpStatusCode: Int?, responseBody: String?, errorMessage: String, durationMs: Int?) {
        self.httpStatusCode = httpStatusCode
        self.responseBody = responseBody
        self.errorMessage = errorMessage
        self.requestDurationMs = durationMs
        self.success = false
    }
}
