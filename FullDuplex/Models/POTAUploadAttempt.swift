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
    @Attribute(.transformable(by: DictionaryTransformer.self))
    var requestHeaders: [String: String] = [:]
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
        self.requestHeaders = requestHeaders
        self.filename = filename
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

// Custom transformer for [String: String] dictionary
final class DictionaryTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass {
        NSData.self
    }

    override class func allowsReverseTransformation() -> Bool {
        true
    }

    override func transformedValue(_ value: Any?) -> Any? {
        guard let dict = value as? [String: String] else { return nil }
        return try? JSONEncoder().encode(dict)
    }

    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    static func register() {
        ValueTransformer.setValueTransformer(
            DictionaryTransformer(),
            forName: NSValueTransformerName("DictionaryTransformer")
        )
    }
}
