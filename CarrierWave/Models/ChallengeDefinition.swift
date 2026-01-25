import Foundation
import SwiftData

// MARK: - ChallengeDefinition

@Model
final class ChallengeDefinition {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        sourceURL: String,
        version: Int = 1,
        name: String,
        descriptionText: String,
        author: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        type: ChallengeType,
        configurationData: Data,
        source: ChallengeSource? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.version = version
        self.name = name
        self.descriptionText = descriptionText
        self.author = author
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.type = type
        self.configurationData = configurationData
        self.source = source
    }

    // MARK: Internal

    var id: UUID
    var sourceURL: String
    var version: Int

    // Metadata (stored directly for queryability)
    var name: String
    var descriptionText: String
    var author: String
    var createdAt: Date
    var updatedAt: Date

    var type: ChallengeType

    /// Configuration stored as JSON
    var configurationData: Data

    var source: ChallengeSource?

    @Relationship(deleteRule: .cascade, inverse: \ChallengeParticipation.challengeDefinition)
    var participations: [ChallengeParticipation] = []

    // MARK: - Configuration Access

    var configuration: ChallengeConfiguration? {
        try? JSONDecoder().decode(ChallengeConfiguration.self, from: configurationData)
    }

    var goals: [ChallengeGoal] {
        configuration?.goals ?? []
    }

    var tiers: [ChallengeTier] {
        configuration?.tiers ?? []
    }

    var criteria: QualificationCriteria? {
        configuration?.criteria
    }

    var scoring: ScoringConfig? {
        configuration?.scoring
    }

    var timeConstraints: TimeConstraints? {
        configuration?.timeConstraints
    }

    var badges: [ChallengeBadge] {
        configuration?.badges ?? []
    }

    var historicalQSOsAllowed: Bool {
        configuration?.historicalQSOsAllowed ?? false
    }

    // MARK: - Convenience

    /// Total number of goals for collection challenges
    var totalGoals: Int {
        goals.count
    }

    /// Target value for cumulative challenges
    var targetValue: Int? {
        goals.first?.targetValue
    }

    /// Whether this challenge has time constraints
    var isTimeBounded: Bool {
        timeConstraints != nil
    }

    /// Time remaining for time-bounded challenges
    var timeRemaining: TimeInterval? {
        guard let constraints = timeConstraints,
              let endDate = constraints.endDate
        else {
            return nil
        }
        let remaining = endDate.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    /// Whether the challenge has ended
    var hasEnded: Bool {
        guard let constraints = timeConstraints,
              let endDate = constraints.endDate
        else {
            return false
        }
        return Date() > endDate
    }

    /// Sorted tiers by order
    var sortedTiers: [ChallengeTier] {
        tiers.sorted { $0.order < $1.order }
    }
}

// MARK: - Factory

extension ChallengeDefinition {
    /// Create from API DTO
    static func from(
        dto: ChallengeDefinitionDTO,
        source: ChallengeSource?
    ) throws -> ChallengeDefinition {
        let configData = try JSONEncoder().encode(dto.configuration)

        return ChallengeDefinition(
            id: dto.id,
            sourceURL: dto.sourceURL,
            version: dto.version,
            name: dto.metadata.name,
            descriptionText: dto.metadata.description,
            author: dto.metadata.author,
            createdAt: dto.metadata.createdAt,
            updatedAt: dto.metadata.updatedAt,
            type: dto.type,
            configurationData: configData,
            source: source
        )
    }
}
