import Foundation

// MARK: - ChallengeType

enum ChallengeType: String, Codable, CaseIterable {
    case collection
    case cumulative
    case timeBounded
}

// MARK: - ParticipationStatus

enum ParticipationStatus: String, Codable, CaseIterable {
    case active
    case completed
    case left
    case expired
}

// MARK: - ChallengeSourceType

enum ChallengeSourceType: String, Codable, CaseIterable {
    case official
    case community
    case invite
}

// MARK: - ScoringMethod

enum ScoringMethod: String, Codable, CaseIterable {
    case percentage
    case count
    case points
    case weighted
}

// MARK: - TimeConstraintType

enum TimeConstraintType: String, Codable {
    case calendar
    case relative
}

// MARK: - ChallengeMetadata

struct ChallengeMetadata: Codable, Equatable {
    var name: String
    var description: String
    var author: String
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - ChallengeGoal

struct ChallengeGoal: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: String?
    var metadata: [String: String]?

    // For cumulative challenges
    var targetValue: Int?
    var unit: String?
}

// MARK: - ChallengeTier

struct ChallengeTier: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var threshold: Int
    var badgeId: String?
    var order: Int
}

// MARK: - QualificationCriteria

struct QualificationCriteria: Codable, Equatable {
    var bands: [String]?
    var modes: [String]?
    var requiredFields: [FieldRequirement]?
    var dateRange: ChallengeDateRange?
    var matchRules: [MatchRule]?
}

// MARK: - FieldRequirement

struct FieldRequirement: Codable, Equatable {
    var fieldName: String
    var mustExist: Bool
    var pattern: String?
}

// MARK: - ChallengeDateRange

struct ChallengeDateRange: Codable, Equatable {
    var startDate: Date
    var endDate: Date
}

// MARK: - MatchRule

struct MatchRule: Codable, Equatable {
    var qsoField: String
    var goalField: String
    var transformation: MatchTransformation?
    var validationRegex: String?
}

// MARK: - MatchTransformation

enum MatchTransformation: String, Codable {
    case uppercase
    case lowercase
    case stripPrefix
    case stripSuffix
}

// MARK: - ScoringConfig

struct ScoringConfig: Codable, Equatable {
    var method: ScoringMethod
    var weights: [WeightRule]?
    var tiebreaker: TiebreakerRule?
    var displayFormat: String?
}

// MARK: - WeightRule

struct WeightRule: Codable, Equatable {
    var condition: String
    var multiplier: Double
}

// MARK: - TiebreakerRule

enum TiebreakerRule: String, Codable {
    case earliestCompletion
    case mostRecent
    case alphabetical
}

// MARK: - TimeConstraints

struct TimeConstraints: Codable, Equatable {
    var type: TimeConstraintType
    var startDate: Date?
    var endDate: Date?
    var durationSeconds: Int?
    var timezone: String?
}

// MARK: - ChallengeBadge

struct ChallengeBadge: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var description: String
    var imageURL: String
    var tier: String?
}

// MARK: - InviteConfig

struct InviteConfig: Codable, Equatable {
    var maxParticipants: Int?
    var expiresAt: Date?
    var participantCount: Int
}

// MARK: - ChallengeProgress

struct ChallengeProgress: Codable, Equatable {
    // MARK: Lifecycle

    init(
        completedGoals: [String] = [],
        currentValue: Int = 0,
        percentage: Double = 0,
        score: Int = 0,
        qualifyingQSOIds: [UUID] = [],
        lastUpdated: Date = Date()
    ) {
        self.completedGoals = completedGoals
        self.currentValue = currentValue
        self.percentage = percentage
        self.score = score
        self.qualifyingQSOIds = qualifyingQSOIds
        self.lastUpdated = lastUpdated
    }

    // MARK: Internal

    var completedGoals: [String]
    var currentValue: Int
    var percentage: Double
    var score: Int
    var qualifyingQSOIds: [UUID]
    var lastUpdated: Date
}

// MARK: - LeaderboardEntry

struct LeaderboardEntry: Codable, Identifiable, Equatable {
    var rank: Int
    var callsign: String
    var score: Int
    var progress: Double
    var currentTier: String?
    var completedAt: Date?
    var isCurrentUser: Bool

    var id: String { callsign }
}

// MARK: - ChallengeConfiguration

/// Combined configuration stored as JSON in ChallengeDefinition
struct ChallengeConfiguration: Codable, Equatable {
    var goals: [ChallengeGoal]
    var tiers: [ChallengeTier]?
    var criteria: QualificationCriteria
    var scoring: ScoringConfig
    var timeConstraints: TimeConstraints?
    var badges: [ChallengeBadge]?
    var historicalQSOsAllowed: Bool
    var inviteConfig: InviteConfig?
}

// MARK: - ChallengeListResponse

struct ChallengeListResponse: Codable {
    var challenges: [ChallengeDefinitionDTO]
}

// MARK: - ChallengeDefinitionDTO

struct ChallengeDefinitionDTO: Codable, Identifiable {
    var id: UUID
    var sourceURL: String
    var version: Int
    var metadata: ChallengeMetadata
    var type: ChallengeType
    var configuration: ChallengeConfiguration
}

// MARK: - LeaderboardResponse

struct LeaderboardResponse: Codable {
    var challengeId: UUID
    var entries: [LeaderboardEntry]
    var lastUpdated: Date
}

// MARK: - JoinChallengeRequest

struct JoinChallengeRequest: Codable {
    var callsign: String
    var token: String?
}

// MARK: - JoinChallengeResponse

struct JoinChallengeResponse: Codable {
    var participationId: UUID
    var joinedAt: Date
}

// MARK: - ProgressReportRequest

struct ProgressReportRequest: Codable {
    var participationId: UUID
    var progress: ChallengeProgress
}

// MARK: - ProgressReportResponse

struct ProgressReportResponse: Codable {
    var accepted: Bool
    var serverProgress: ChallengeProgress?
}
