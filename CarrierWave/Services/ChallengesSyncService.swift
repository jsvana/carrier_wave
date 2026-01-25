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
        let officialType = ChallengeSourceType.official
        let descriptor = FetchDescriptor<ChallengeSource>(
            predicate: #Predicate { $0.type == officialType }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }

        let official = ChallengeSource(
            type: .official,
            url: "https://challenges.carrierwave.app/api",
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
        let dtos = try await client.fetchChallenges(from: source.url)

        // Fetch existing challenges for this source
        let sourceId = source.id
        let descriptor = FetchDescriptor<ChallengeDefinition>(
            predicate: #Predicate { $0.source?.id == sourceId }
        )
        let existing = try modelContext.fetch(descriptor)
        let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        for dto in dtos {
            if let existing = existingById[dto.id] {
                // Update existing if version changed
                if dto.version > existing.version {
                    try updateChallengeDefinition(existing, from: dto)
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
    func joinChallenge(_ definition: ChallengeDefinition, token: String? = nil) async throws {
        guard let sourceURL = definition.source?.url else {
            throw ChallengesError.invalidServerURL
        }

        let response = try await client.joinChallenge(
            id: definition.id,
            sourceURL: sourceURL,
            token: token
        )

        guard let callsign = await client.getCallsign() else {
            throw ChallengesError.notAuthenticated
        }

        let participation = ChallengeParticipation.join(
            challenge: definition,
            userId: callsign,
            serverParticipationId: response.participationId
        )
        modelContext.insert(participation)

        // Evaluate historical QSOs
        progressEngine.evaluateHistoricalQSOs(for: participation)

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
              let serverParticipationId = participation.serverParticipationId
        else {
            return
        }

        let response = try await client.reportProgress(
            participationId: serverParticipationId,
            progress: participation.progress,
            sourceURL: sourceURL,
            challengeId: definition.id
        )

        if response.accepted {
            participation.lastSyncedAt = Date()
            participation.needsSync = false
        }

        // If server returned different progress, update local
        if let serverProgress = response.serverProgress {
            participation.progress = serverProgress
        }

        try modelContext.save()
    }

    /// Sync all participations that need sync
    func syncAllProgress() async throws {
        let activeStatus = ParticipationStatus.active
        let descriptor = FetchDescriptor<ChallengeParticipation>(
            predicate: #Predicate { $0.needsSync && $0.status == activeStatus }
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

        let response = try await client.fetchLeaderboard(
            challengeId: definition.id,
            sourceURL: sourceURL
        )

        // Update or create cache
        let challengeId = definition.id
        let cacheDescriptor = FetchDescriptor<LeaderboardCache>(
            predicate: #Predicate { $0.challengeId == challengeId }
        )

        if let cache = try modelContext.fetch(cacheDescriptor).first {
            cache.update(from: response)
        } else {
            let cache = LeaderboardCache.from(response: response)
            modelContext.insert(cache)
        }

        try modelContext.save()

        // Mark current user's entry
        var entries = response.entries
        if let callsign = await client.getCallsign() {
            entries = entries.map { entry in
                var updated = entry
                updated.isCurrentUser = entry.callsign.uppercased() == callsign.uppercased()
                return updated
            }
        }

        return entries
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
        let activeStatus = ParticipationStatus.active
        let descriptor = FetchDescriptor<ChallengeParticipation>(
            predicate: #Predicate { $0.status == activeStatus },
            sortBy: [SortDescriptor(\.joinedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch all completed participations
    func fetchCompletedParticipations() throws -> [ChallengeParticipation] {
        let completedStatus = ParticipationStatus.completed
        let descriptor = FetchDescriptor<ChallengeParticipation>(
            predicate: #Predicate { $0.status == completedStatus },
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: Private

    /// Update an existing challenge definition
    private func updateChallengeDefinition(
        _ definition: ChallengeDefinition,
        from dto: ChallengeDefinitionDTO
    ) throws {
        definition.version = dto.version
        definition.name = dto.metadata.name
        definition.descriptionText = dto.metadata.description
        definition.author = dto.metadata.author
        definition.updatedAt = dto.metadata.updatedAt
        definition.configurationData = try JSONEncoder().encode(dto.configuration)

        // Re-evaluate progress for all participations
        for participation in definition.participations {
            progressEngine.reevaluateAllQSOs(for: participation)
        }
    }
}
