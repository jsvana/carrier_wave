import Foundation
import SwiftData

@Model
final class UploadDestination {
    var id: UUID
    var type: DestinationType
    var isEnabled: Bool
    var lastSyncAt: Date?

    init(
        id: UUID = UUID(),
        type: DestinationType,
        isEnabled: Bool = false,
        lastSyncAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.isEnabled = isEnabled
        self.lastSyncAt = lastSyncAt
    }
}

// Note: Credentials (API keys, tokens) stored in Keychain, not SwiftData
