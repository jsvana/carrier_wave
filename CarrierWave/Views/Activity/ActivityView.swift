import SwiftData
import SwiftUI

// MARK: - ActivityView

struct ActivityView: View {
    // MARK: Internal

    let tourState: TourState

    @Environment(\.modelContext) var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    challengesSection
                    activityFeedSection
                }
                .padding()
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        FriendsListView()
                    } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("Friends")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        if isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh")
                }
            }
            .onAppear {
                if syncService == nil {
                    syncService = ChallengesSyncService(modelContext: modelContext)
                }
                if friendsSyncService == nil {
                    friendsSyncService = FriendsSyncService(modelContext: modelContext)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { showingError = false }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
            .sheet(isPresented: $showingInviteSheet) {
                if let invite = pendingInvite {
                    InviteJoinSheet(
                        invite: invite,
                        syncService: syncService,
                        isJoining: $isJoiningFromInvite,
                        onComplete: { success in
                            showingInviteSheet = false
                            pendingInvite = nil
                            if !success {
                                errorMessage = "Failed to join challenge"
                                showingError = true
                            }
                        }
                    )
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didReceiveChallengeInvite)
            ) { notification in
                handleInviteNotification(notification)
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .didSyncQSOs)
            ) { _ in
                Task { await evaluateNewQSOs() }
            }
            .miniTour(.challenges, tourState: tourState)
        }
    }

    // MARK: Private

    @State private var isRefreshing = false

    @Query(sort: \ChallengeParticipation.joinedAt, order: .reverse)
    private var allParticipations: [ChallengeParticipation]

    @Query(sort: \ActivityItem.timestamp, order: .reverse)
    private var allActivityItems: [ActivityItem]

    @Query private var clubs: [Club]

    @Query(filter: #Predicate<Friendship> { $0.statusRawValue == "accepted" })
    private var acceptedFriends: [Friendship]

    @State private var selectedFilter: FeedFilter = .all

    @State private var syncService: ChallengesSyncService?
    @State private var friendsSyncService: FriendsSyncService?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Invite handling
    @State private var pendingInvite: PendingChallengeInvite?
    @State private var showingInviteSheet = false
    @State private var isJoiningFromInvite = false

    private var activeParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .active }
    }

    private var completedParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .completed }
    }

    private var filteredActivityItems: [ActivityItem] {
        switch selectedFilter {
        case .all:
            return allActivityItems
        case .friends:
            let friendCallsigns = Set(acceptedFriends.map { $0.friendCallsign.uppercased() })
            return allActivityItems.filter { friendCallsigns.contains($0.callsign.uppercased()) }
        case let .club(clubId):
            guard let club = clubs.first(where: { $0.id == clubId }) else {
                return []
            }
            return allActivityItems.filter { club.isMember(callsign: $0.callsign) }
        }
    }

    // MARK: - Challenges Section

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Your Challenges")
                    .font(.headline)
                Spacer()
                NavigationLink {
                    BrowseChallengesView()
                } label: {
                    Text("Browse")
                        .font(.subheadline)
                }
            }

            if activeParticipations.isEmpty, completedParticipations.isEmpty {
                challengesEmptyState
            } else {
                if !activeParticipations.isEmpty {
                    ForEach(activeParticipations) { participation in
                        NavigationLink {
                            ChallengeDetailView(participation: participation)
                        } label: {
                            ChallengeProgressCard(participation: participation)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !completedParticipations.isEmpty {
                    DisclosureGroup("Completed (\(completedParticipations.count))") {
                        ForEach(completedParticipations) { participation in
                            NavigationLink {
                                ChallengeDetailView(participation: participation)
                            } label: {
                                CompletedChallengeCard(participation: participation)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private var challengesEmptyState: some View {
        VStack(spacing: 8) {
            Text("No active challenges")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NavigationLink {
                BrowseChallengesView()
            } label: {
                Text("Browse Challenges")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: - Activity Feed Section

    private var activityFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)

            FilterBar(selectedFilter: $selectedFilter, clubs: clubs)

            if filteredActivityItems.isEmpty {
                activityEmptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredActivityItems) { item in
                        ActivityItemRow(item: item) {
                            shareActivity(item)
                        }
                    }
                }
            }
        }
    }

    private var activityEmptyState: some View {
        ContentUnavailableView(
            "No Activity Yet",
            systemImage: "person.2",
            description: Text("Activity from friends and clubs will appear here.")
        )
        .padding(.vertical, 24)
    }

    private func shareActivity(_ item: ActivityItem) {
        // Sharing will be implemented in Phase 7
        print("Share activity: \(item.callsign) - \(item.activityType.displayName)")
    }

    private func refresh() async {
        guard let syncService else {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            try await syncService.refreshChallenges(forceUpdate: true)
            for participation in activeParticipations {
                syncService.progressEngine.reevaluateAllQSOs(for: participation)
            }
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func handleInviteNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let source = userInfo["source"] as? String,
              let challengeId = userInfo["challengeId"] as? UUID
        else {
            return
        }

        let token = userInfo["token"] as? String

        pendingInvite = PendingChallengeInvite(
            sourceURL: source,
            challengeId: challengeId,
            token: token
        )
        showingInviteSheet = true
    }

    private func evaluateNewQSOs() async {
        guard let syncService else {
            return
        }

        let descriptor = FetchDescriptor<QSO>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let recentQSOs = try modelContext.fetch(descriptor)
            for qso in recentQSOs.prefix(100) {
                syncService.progressEngine.evaluateQSO(qso, notificationsEnabled: false)
            }
            try modelContext.save()
        } catch {
            // Silently fail - background operation
        }
    }
}

#Preview {
    ActivityView(tourState: TourState())
        .modelContainer(
            for: [
                ChallengeSource.self,
                ChallengeDefinition.self,
                ChallengeParticipation.self,
                ActivityItem.self,
                Club.self,
                Friendship.self,
            ], inMemory: true
        )
}
