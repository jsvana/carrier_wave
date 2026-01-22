import Foundation

enum POTAJobStatus: Int, Codable {
    case pending = 0
    case processing = 1
    case completed = 2
    case failed = 3
    case duplicate = 7
    case error = -1

    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .duplicate: return "Duplicate"
        case .error: return "Error"
        }
    }

    var color: String {
        switch self {
        case .pending, .processing: return "orange"
        case .completed: return "green"
        case .failed, .error: return "red"
        case .duplicate: return "yellow"
        }
    }
}

struct POTAJob: Identifiable, Codable {
    let jobId: Int
    let status: POTAJobStatus
    let submitted: Date
    let processed: Date?
    let reference: String
    let parkName: String?
    let location: String?
    let totalQsos: Int
    let insertedQsos: Int
    let callsignUsed: String?
    let userComment: String?

    var id: Int { jobId }

    enum CodingKeys: String, CodingKey {
        case jobId, status, submitted, processed, reference, location
        case parkName = "parkName"
        case totalQsos = "total"
        case insertedQsos = "inserted"
        case callsignUsed = "callsignUsed"
        case userComment = "userComment"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jobId = try container.decode(Int.self, forKey: .jobId)
        let statusInt = try container.decode(Int.self, forKey: .status)
        status = POTAJobStatus(rawValue: statusInt) ?? .error
        reference = try container.decode(String.self, forKey: .reference)
        parkName = try container.decodeIfPresent(String.self, forKey: .parkName)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        totalQsos = try container.decodeIfPresent(Int.self, forKey: .totalQsos) ?? -1
        insertedQsos = try container.decodeIfPresent(Int.self, forKey: .insertedQsos) ?? -1
        callsignUsed = try container.decodeIfPresent(String.self, forKey: .callsignUsed)
        userComment = try container.decodeIfPresent(String.self, forKey: .userComment)

        // Parse dates
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        let submittedStr = try container.decode(String.self, forKey: .submitted)
        submitted = dateFormatter.date(from: submittedStr)
            ?? fallbackFormatter.date(from: submittedStr)
            ?? Date()

        if let processedStr = try container.decodeIfPresent(String.self, forKey: .processed) {
            processed = dateFormatter.date(from: processedStr)
                ?? fallbackFormatter.date(from: processedStr)
        } else {
            processed = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobId, forKey: .jobId)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(reference, forKey: .reference)
        try container.encodeIfPresent(parkName, forKey: .parkName)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(totalQsos, forKey: .totalQsos)
        try container.encode(insertedQsos, forKey: .insertedQsos)
        try container.encodeIfPresent(callsignUsed, forKey: .callsignUsed)
        try container.encodeIfPresent(userComment, forKey: .userComment)

        let dateFormatter = ISO8601DateFormatter()
        try container.encode(dateFormatter.string(from: submitted), forKey: .submitted)
        if let processed = processed {
            try container.encode(dateFormatter.string(from: processed), forKey: .processed)
        }
    }

    // For testing/previews
    init(jobId: Int, status: POTAJobStatus, submitted: Date, processed: Date?,
         reference: String, parkName: String?, location: String?,
         totalQsos: Int, insertedQsos: Int, callsignUsed: String?, userComment: String?) {
        self.jobId = jobId
        self.status = status
        self.submitted = submitted
        self.processed = processed
        self.reference = reference
        self.parkName = parkName
        self.location = location
        self.totalQsos = totalQsos
        self.insertedQsos = insertedQsos
        self.callsignUsed = callsignUsed
        self.userComment = userComment
    }
}
