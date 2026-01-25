import Combine
import Foundation
import SwiftData

@MainActor
final class ChallengesSyncService: ObservableObject {
    // MARK: Lifecycle

    init(modelContext: ModelContext, client: ChallengesClient = ChallengesClient()) {
        self.modelContext = modelContext
        self.client = client
        progressEngine = ChallengeProgressEngine(modelContext: modelContext)
    }

    // MARK: Internal

    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    let modelContext: ModelContext
    let client: ChallengesClient
    let progressEngine: ChallengeProgressEngine

    /// Default polling interval for leaderboards (30 seconds)
    let leaderboardPollingInterval: TimeInterval = 30

    /// Check if challenges sync is enabled
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "challengesSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "challengesSyncEnabled") }
    }

    // MARK: - Source Management

    /// Fetch the official challenge source (creates if needed)
    func getOrCreateOfficialSource() throws -> ChallengeSource {
        let officialRaw = ChallengeSourceType.official.rawValue
        let descriptor = FetchDescriptor<ChallengeSource>(
            predicate: #Predicate { $0.typeRawValue == officialRaw }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let official = ChallengeSource(
            type: .official,
            url: "https://challenges.example.com",
            name: "Carrier Wave Official"
        )
        modelContext.insert(official)
        try modelContext.save()
        return official
    }

    /// Add a community source
    func addCommunitySource(url: String, name: String) throws -> ChallengeSource {
        let source = ChallengeSource(
            type: .community,
            url: url,
            name: name
        )
        modelContext.insert(source)
        try modelContext.save()
        return source
    }

    /// Remove a source (and its challenges)
    func removeSource(_ source: ChallengeSource) throws {
        modelContext.delete(source)
        try modelContext.save()
    }

    /// Fetch all enabled sources
    func fetchEnabledSources() throws -> [ChallengeSource] {
        let descriptor = FetchDescriptor<ChallengeSource>(
            predicate: #Predicate { $0.isEnabled }
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Challenge Fetching

    /// Refresh challenges from all enabled sources
    func refreshChallenges() async throws {
        isSyncing = true
        syncError = nil

        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        let sources = try fetchEnabledSources()

        for source in sources {
            do {
                try await refreshChallenges(from: source)
            } catch {
                source.lastError = error.localizedDescription
                syncError = "Failed to refresh \(source.name): \(error.localizedDescription)"
            }
        }

        try modelContext.save()
    }

    /// Refresh challenges from a specific source
    func refreshChallenges(from source: ChallengeSource) async throws {
        let listData = try await client.fetchChallenges(from: source.url, active: true)

        // Fetch existing challenges for this source
        let sourceId = source.id
        let descriptor = FetchDescriptor<ChallengeDefinition>(
            predicate: #Predicate { $0.source?.id == sourceId }
        )
        let existing = try modelContext.fetch(descriptor)
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        // Fetch full details for each challenge in the list
        for listItem in listData.challenges {
            let dto = try await client.fetchChallenge(id: listItem.id, from: source.url)

            if let existing = existingById[dto.id] {
                // Update existing if version changed
                if dto.version > existing.version {
                    try existing.update(from: dto)
                    // Re-evaluate progress for all participations
                    for participation in existing.participations {
                        progressEngine.reevaluateAllQSOs(for: participation)
                    }
                }
            } else {
                // Create new
                let definition = try ChallengeDefinition.from(dto: dto, source: source)
                modelContext.insert(definition)
            }
        }

        source.lastFetched = Date()
        source.lastError = nil
    }

    // MARK: - Participation

    /// Join a challenge
    func joinChallenge(_ definition: ChallengeDefinition, inviteToken: String? = nil) async throws {
        guard let sourceURL = definition.source?.url else {
            throw ChallengesError.invalidServerURL
        }

        let callsign = UserDefaults.standard.string(forKey: "userCallsign") ?? ""
        guard !callsign.isEmpty else {
            throw ChallengesError.notAuthenticated
        }

        let response = try await client.joinChallenge(
            id: definition.id,
            sourceURL: sourceURL,
            callsign: callsign,
            inviteToken: inviteToken
        )

        let participation = ChallengeParticipation.join(
            challenge: definition,
            userId: callsign,
            serverParticipationId: response.participationId
        )
        participation.historicalAllowed = response.historicalAllowed
        modelContext.insert(participation)

        // Evaluate historical QSOs if allowed
        if response.historicalAllowed {
            progressEngine.evaluateHistoricalQSOs(for: participation)
        }

        try modelContext.save()

        // Report initial progress
        try await reportProgress(participation)
    }

    /// Leave a challenge
    func leaveChallenge(_ participation: ChallengeParticipation) async throws {
        guard let definition = participation.challengeDefinition,
              let sourceURL = definition.source?.url
        else {
            throw ChallengesError.invalidServerURL
        }

        try await client.leaveChallenge(id: definition.id, sourceURL: sourceURL)

        participation.status = .left
        try modelContext.save()
    }

    // MARK: - Progress Sync

    /// Report progress for a participation to the server
    func reportProgress(_ participation: ChallengeParticipation) async throws {
        guard let definition = participation.challengeDefinition,
              let sourceURL = definition.source?.url,
              participation.serverParticipationId != nil
        else {
            return
        }

        let localProgress = participation.progress
        let report = ProgressReportRequest(
            completedGoals: localProgress.completedGoals,
            currentValue: localProgress.currentValue,
            qualifyingQsoCount: localProgress.qualifyingQSOIds.count,
            lastQsoDate: localProgress.lastUpdated
        )
        let response = try await client.reportProgress(
            challengeId: definition.id,
            report: report,
            sourceURL: sourceURL
        )

        if response.accepted {
            participation.lastSyncedAt = Date()
            participation.needsSync = false
        }

        // Update local progress with server values
        let serverProgress = response.serverProgress
        participation.progress = ChallengeProgress(
            completedGoals: serverProgress.completedGoals,
            currentValue: serverProgress.currentValue,
            percentage: serverProgress.percentage,
            score: serverProgress.score,
            qualifyingQSOIds: localProgress.qualifyingQSOIds,
            lastUpdated: Date()
        )

        // Update rank if provided
        if let rank = serverProgress.rank {
            participation.serverRank = rank
        }

        try modelContext.save()
    }

    /// Sync all participations that need sync
    func syncAllProgress() async throws {
        let activeRaw = ParticipationStatus.active.rawValue
        let descriptor = FetchDescriptor<ChallengeParticipation>(
            predicate: #Predicate { $0.needsSync && $0.statusRawValue == activeRaw }
        )
        let participations = try modelContext.fetch(descriptor)

        for participation in participations {
            do {
                try await reportProgress(participation)
            } catch {
                // Log error but continue with others
                syncError = "Failed to sync progress: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Leaderboards

    /// Fetch and cache leaderboard for a challenge
    func fetchLeaderboard(for definition: ChallengeDefinition) async throws -> [LeaderboardEntry] {
        guard let sourceURL = definition.source?.url else {
            throw ChallengesError.invalidServerURL
        }

        let leaderboardData = try await client.fetchLeaderboard(
            challengeId: definition.id,
            sourceURL: sourceURL
        )

        // Update or create cache
        let challengeId = definition.id
        let cacheDescriptor = FetchDescriptor<LeaderboardCache>(
            predicate: #Predicate { $0.challengeId == challengeId }
        )

        if let cache = try modelContext.fetch(cacheDescriptor).first {
            cache.update(from: leaderboardData)
        } else {
            let cache = LeaderboardCache.from(challengeId: challengeId, data: leaderboardData)
            modelContext.insert(cache)
        }

        try modelContext.save()

        return leaderboardData.leaderboard
    }

    /// Get cached leaderboard (returns nil if cache is stale)
    func getCachedLeaderboard(
        for definition: ChallengeDefinition,
        maxAge: TimeInterval = 30
    ) throws -> [LeaderboardEntry]? {
        let challengeId = definition.id
        let cacheDescriptor = FetchDescriptor<LeaderboardCache>(
            predicate: #Predicate { $0.challengeId == challengeId }
        )

        guard let cache = try modelContext.fetch(cacheDescriptor).first,
              !cache.isStale(olderThan: maxAge)
        else {
            return nil
        }

        return cache.entries
    }

    // MARK: - QSO Integration

    /// Called when a new QSO is logged - evaluates against all active challenges
    func onQSOLogged(_ qso: QSO) async throws {
        progressEngine.evaluateQSO(qso)

        // Sync updated participations
        if isEnabled {
            try await syncAllProgress()
        }
    }

    /// Called when QSOs are imported - batch evaluate
    func onQSOsImported(_ qsos: [QSO]) async throws {
        for qso in qsos {
            progressEngine.evaluateQSO(qso, notificationsEnabled: false)
        }

        // Single sync after batch
        if isEnabled {
            try await syncAllProgress()
        }
    }

    // MARK: - Active Participations

    /// Fetch all active participations
    func fetchActiveParticipations() throws -> [ChallengeParticipation] {
        let activeRaw = ParticipationStatus.active.rawValue
        let descriptor = FetchDescriptor<ChallengeParticipation>(
            predicate: #Predicate { $0.statusRawValue == activeRaw },
            sortBy: [SortDescriptor(\.joinedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all completed participations
    func fetchCompletedParticipations() throws -> [ChallengeParticipation] {
        let completedRaw = ParticipationStatus.completed.rawValue
        let descriptor = FetchDescriptor<ChallengeParticipation>(
            predicate: #Predicate { $0.statusRawValue == completedRaw },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }
}
