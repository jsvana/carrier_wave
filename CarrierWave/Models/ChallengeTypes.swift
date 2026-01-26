import Foundation

// MARK: - ChallengeType

enum ChallengeType: String, Codable, CaseIterable, @unchecked Sendable {
    case collection
    case cumulative
    case timeBounded
}

// MARK: - ParticipationStatus

enum ParticipationStatus: String, Codable, CaseIterable, @unchecked Sendable {
    case active
    case completed
    case left
    case expired
}

// MARK: - ChallengeSourceType

enum ChallengeSourceType: String, Codable, CaseIterable, @unchecked Sendable {
    case official
    case community
    case invite
}

// MARK: - ScoringMethod

enum ScoringMethod: String, Codable, CaseIterable, @unchecked Sendable {
    case percentage
    case count
    case points
    case weighted
}

// MARK: - TimeConstraintType

enum TimeConstraintType: String, Codable, @unchecked Sendable {
    case calendar
    case relative
}

// MARK: - ChallengeMetadata

struct ChallengeMetadata: Codable, Equatable, @unchecked Sendable {
    var name: String
    var description: String
    var author: String
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - ChallengeGoal

struct ChallengeGoal: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var category: String?
    var metadata: [String: String]?

    // For cumulative challenges
    var targetValue: Int?
    var unit: String?
}

// MARK: - ChallengeTier

struct ChallengeTier: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var threshold: Int
    var badgeId: String?
    var order: Int
}

// MARK: - QualificationCriteria

struct QualificationCriteria: Codable, Equatable, @unchecked Sendable {
    var bands: [String]?
    var modes: [String]?
    var requiredFields: [FieldRequirement]?
    var dateRange: ChallengeDateRange?
    var matchRules: [MatchRule]?
}

// MARK: - FieldRequirement

struct FieldRequirement: Codable, Equatable, @unchecked Sendable {
    var fieldName: String
    var mustExist: Bool
    var pattern: String?
}

// MARK: - ChallengeDateRange

struct ChallengeDateRange: Codable, Equatable, @unchecked Sendable {
    var startDate: Date
    var endDate: Date
}

// MARK: - MatchRule

struct MatchRule: Codable, Equatable, @unchecked Sendable {
    var qsoField: String
    var goalField: String
    var transformation: MatchTransformation?
    var validationRegex: String?
}

// MARK: - MatchTransformation

enum MatchTransformation: String, Codable, @unchecked Sendable {
    case uppercase
    case lowercase
    case stripPrefix
    case stripSuffix
}

// MARK: - ScoringConfig

struct ScoringConfig: Codable, Equatable, @unchecked Sendable {
    var method: ScoringMethod
    var weights: [WeightRule]?
    var tiebreaker: TiebreakerRule?
    var displayFormat: String?
}

// MARK: - WeightRule

struct WeightRule: Codable, Equatable, @unchecked Sendable {
    var condition: String
    var multiplier: Double
}

// MARK: - TiebreakerRule

enum TiebreakerRule: String, Codable, @unchecked Sendable {
    case earliestCompletion
    case mostRecent
    case alphabetical
}

// MARK: - TimeConstraints

struct TimeConstraints: Codable, Equatable, @unchecked Sendable {
    var type: TimeConstraintType
    var startDate: Date?
    var endDate: Date?
    var durationSeconds: Int?
    var timezone: String?
}

// MARK: - ChallengeBadge

struct ChallengeBadge: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var description: String
    var imageURL: String
    var tier: String?
}

// MARK: - InviteConfig

struct InviteConfig: Codable, Equatable, @unchecked Sendable {
    var maxParticipants: Int?
    var expiresAt: Date?
    var participantCount: Int
}

// MARK: - ChallengeProgress

struct ChallengeProgress: Codable, Equatable, @unchecked Sendable {
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

struct LeaderboardEntry: Codable, Identifiable, Equatable, @unchecked Sendable {
    var rank: Int
    var callsign: String
    var score: Int
    var currentTier: String?
    var completedAt: Date?

    var id: String { callsign }
}

// MARK: - ChallengeConfiguration

/// Combined configuration stored as JSON in ChallengeDefinition
struct ChallengeConfiguration: Codable, Equatable, @unchecked Sendable {
    var goals: [ChallengeGoal]
    var tiers: [ChallengeTier]?
    var criteria: QualificationCriteria
    var scoring: ScoringConfig
    var timeConstraints: TimeConstraints?
    var badges: [ChallengeBadge]?
    var historicalQSOsAllowed: Bool
    var inviteConfig: InviteConfig?
}

// MARK: - APIResponse

struct APIResponse<T: Codable>: Codable, @unchecked Sendable {
    var data: T
}

// MARK: - APIError

struct APIError: Codable, @unchecked Sendable {
    var code: String
    var message: String
    var details: [String: String]?
}

// MARK: - APIErrorResponse

struct APIErrorResponse: Codable, @unchecked Sendable {
    var error: APIError
}

// MARK: - ChallengeListData

struct ChallengeListData: Codable, @unchecked Sendable {
    var challenges: [ChallengeListItemDTO]
    var total: Int
    var limit: Int
    var offset: Int
}

// MARK: - ChallengeListItemDTO

struct ChallengeListItemDTO: Codable, Identifiable, @unchecked Sendable {
    var id: UUID
    var name: String
    var description: String
    var category: ChallengeCategory
    var type: ChallengeType
    var participantCount: Int
    var isActive: Bool
}

// MARK: - ChallengeCategory

enum ChallengeCategory: String, Codable, CaseIterable, @unchecked Sendable {
    case award
    case event
    case club
    case personal
    case other
}

// MARK: - ChallengeDefinitionDTO

struct ChallengeDefinitionDTO: Codable, Identifiable, @unchecked Sendable {
    var id: UUID
    var version: Int
    var name: String
    var description: String
    var author: String
    var category: ChallengeCategory
    var type: ChallengeType
    var configuration: ChallengeConfigurationDTO
    var badges: [ChallengeBadgeDTO]?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
}

// MARK: - ChallengeConfigurationDTO

struct ChallengeConfigurationDTO: Codable, Equatable, @unchecked Sendable {
    var goals: ChallengeGoalsDTO
    var tiers: [ChallengeTierDTO]?
    var qualificationCriteria: QualificationCriteriaDTO
    var scoring: ScoringConfigDTO
    var historicalQsosAllowed: Bool
}

// MARK: - ChallengeGoalsDTO

struct ChallengeGoalsDTO: Codable, Equatable, @unchecked Sendable {
    var type: String
    var items: [ChallengeGoalItemDTO]?
    var target: Int?
    var unit: String?
}

// MARK: - ChallengeGoalItemDTO

struct ChallengeGoalItemDTO: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
}

// MARK: - ChallengeTierDTO

struct ChallengeTierDTO: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var threshold: Int
}

// MARK: - QualificationCriteriaDTO

struct QualificationCriteriaDTO: Codable, Equatable, @unchecked Sendable {
    var bands: [String]?
    var modes: [String]?
    var requiredFields: [String]?
    var dateRange: DateRangeDTO?
    var matchRules: [MatchRuleDTO]?
}

// MARK: - DateRangeDTO

struct DateRangeDTO: Codable, Equatable, @unchecked Sendable {
    var start: Date
    var end: Date
}

// MARK: - MatchRuleDTO

struct MatchRuleDTO: Codable, Equatable, @unchecked Sendable {
    var qsoField: String
    var goalField: String
}

// MARK: - ScoringConfigDTO

struct ScoringConfigDTO: Codable, Equatable, @unchecked Sendable {
    var method: String
    var displayFormat: String?
}

// MARK: - ChallengeBadgeDTO

struct ChallengeBadgeDTO: Codable, Identifiable, Equatable, @unchecked Sendable {
    var id: String
    var name: String
    var tierId: String?
}

// MARK: - LeaderboardData

struct LeaderboardData: Codable, @unchecked Sendable {
    var leaderboard: [LeaderboardEntry]
    var total: Int
    var userPosition: LeaderboardUserPosition?
    var lastUpdated: Date
}

// MARK: - LeaderboardUserPosition

struct LeaderboardUserPosition: Codable, Equatable, @unchecked Sendable {
    var rank: Int
    var callsign: String
    var score: Int
}

// MARK: - JoinChallengeRequest

struct JoinChallengeRequest: Codable, @unchecked Sendable {
    var callsign: String
    var deviceName: String
    var inviteToken: String?
}

// MARK: - JoinChallengeData

struct JoinChallengeData: Codable, @unchecked Sendable {
    var participationId: UUID
    var deviceToken: String
    var joinedAt: Date
    var status: String
    var historicalAllowed: Bool
}

// MARK: - ProgressReportRequest

struct ProgressReportRequest: Codable, @unchecked Sendable {
    var completedGoals: [String]
    var currentValue: Int
    var qualifyingQsoCount: Int
    var lastQsoDate: Date?
}

// MARK: - ServerProgress

struct ServerProgress: Codable, Equatable, @unchecked Sendable {
    var completedGoals: [String]
    var currentValue: Int
    var percentage: Double
    var score: Int
    var rank: Int?
    var currentTier: String?
}

// MARK: - ProgressReportData

struct ProgressReportData: Codable, @unchecked Sendable {
    var accepted: Bool
    var serverProgress: ServerProgress
    var newBadges: [String]?
}

// MARK: - ParticipatingChallengeDTO

struct ParticipatingChallengeDTO: Codable, Identifiable, @unchecked Sendable {
    var participationId: UUID
    var challengeId: UUID
    var challengeName: String
    var joinedAt: Date
    var status: String

    var id: UUID { participationId }
}
