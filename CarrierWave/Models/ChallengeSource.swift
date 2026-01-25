import Foundation
import SwiftData

@Model
final class ChallengeSource {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        type: ChallengeSourceType,
        url: String,
        name: String,
        isEnabled: Bool = true,
        lastFetched: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.type = type
        self.url = url
        self.name = name
        self.isEnabled = isEnabled
        self.lastFetched = lastFetched
        self.lastError = lastError
    }

    // MARK: Internal

    var id: UUID
    var type: ChallengeSourceType
    var url: String
    var name: String
    var isEnabled: Bool
    var lastFetched: Date?
    var lastError: String?

    @Relationship(deleteRule: .cascade, inverse: \ChallengeDefinition.source)
    var challenges: [ChallengeDefinition] = []

    /// Whether this is the official Carrier Wave source
    var isOfficial: Bool {
        type == .official
    }

    /// Display name with trust indicator
    var displayNameWithTrust: String {
        switch type {
        case .official:
            "\(name) ✓"
        case .community:
            name
        case .invite:
            "\(name) (Invite)"
        }
    }
}
