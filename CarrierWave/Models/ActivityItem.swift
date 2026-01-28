import Foundation
import SwiftData

// MARK: - ActivityItem

@Model
final class ActivityItem {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        callsign: String,
        activityType: ActivityType,
        timestamp: Date = Date(),
        detailsData: Data = Data(),
        isOwn: Bool = false,
        challengeId: UUID? = nil
    ) {
        self.id = id
        self.callsign = callsign
        activityTypeRawValue = activityType.rawValue
        self.timestamp = timestamp
        self.detailsData = detailsData
        self.isOwn = isOwn
        self.challengeId = challengeId
    }

    // MARK: Internal

    var id = UUID()
    var callsign = ""
    var activityTypeRawValue = ActivityType.dxContact.rawValue
    var timestamp = Date()
    var detailsData = Data()
    var isOwn = false
    var challengeId: UUID?

    var activityType: ActivityType {
        get { ActivityType(rawValue: activityTypeRawValue) ?? .dxContact }
        set { activityTypeRawValue = newValue.rawValue }
    }

    var details: ActivityDetails? {
        get {
            ActivityDetails.decode(from: detailsData)
        }
        set {
            detailsData = newValue?.encode() ?? Data()
        }
    }
}

// MARK: - ActivityDetails

struct ActivityDetails: Codable, Sendable {
    // Generic fields that apply to multiple activity types
    var entityName: String? // DXCC entity name
    var entityCode: String? // DXCC entity code
    var band: String?
    var mode: String?
    var distanceKm: Double?
    var workedCallsign: String? // The station worked for DX contacts
    var parkReference: String? // POTA/SOTA reference
    var parkName: String?
    var qsoCount: Int? // For activations
    var streakDays: Int? // For streak activities
    var challengeName: String? // For challenge activities
    var tierName: String? // For tier unlock
    var recordType: String? // For personal bests (e.g., "distance", "qsos_in_day")
    var recordValue: String? // The record value as display string

    // MARK: - Nonisolated Codable Helpers

    /// Decode from data in a nonisolated context (for use with @Model classes)
    static func decode(from data: Data) -> ActivityDetails? {
        try? JSONDecoder().decode(ActivityDetails.self, from: data)
    }

    /// Encode to data in a nonisolated context (for use with @Model classes)
    func encode() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}
