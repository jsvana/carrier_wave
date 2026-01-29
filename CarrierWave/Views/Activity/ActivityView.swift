import SwiftData
import SwiftUI

// MARK: - ActivityView

struct ActivityView: View {
    // MARK: Internal

    let tourState: TourState

    @Environment(\.modelContext) var modelContext
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                if horizontalSizeClass == .regular {
                    // iPad: Side-by-side layout
                    HStack(alignment: .top, spacing: 24) {
                        challengesSection
                            .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
                        activityFeedSection
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                } else {
                    // iPhone: Vertical stack
                    VStack(spacing: 24) {
                        challengesSection
                        activityFeedSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    NavigationLink {
                        FriendsListView()
                    } label: {
                        Image(systemName: "person.2")
                    }
                    .accessibilityLabel("Friends")

                    NavigationLink {
                        ClubsListView()
                    } label: {
                        Image(systemName: "person.3")
                    }
                    .accessibilityLabel("Clubs")
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
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingSummarySheet = true
                    } label: {
                        Label("Share Summary", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .onAppear {
                if syncService == nil {
                    syncService = ChallengesSyncService(modelContext: modelContext)
                }
                if friendsSyncService == nil {
                    friendsSyncService = FriendsSyncService(modelContext: modelContext)
                }
                if clubsSyncService == nil {
                    clubsSyncService = ClubsSyncService(modelContext: modelContext)
                }
                if feedSyncService == nil {
                    feedSyncService = ActivityFeedSyncService(modelContext: modelContext)
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
            .sheet(isPresented: $showingShareSheet) {
                if let item = itemToShare {
                    ShareSheetView(item: item)
                }
            }
            .sheet(isPresented: $showingSummarySheet) {
                SummaryCardSheet(callsign: currentCallsign)
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
    @State private var clubsSyncService: ClubsSyncService?
    @State private var feedSyncService: ActivityFeedSyncService?
    @State private var errorMessage: String?
    @State private var showingError = false

    // Invite handling
    @State private var pendingInvite: PendingChallengeInvite?
    @State private var showingInviteSheet = false
    @State private var isJoiningFromInvite = false

    // Sharing
    @State private var itemToShare: ActivityItem?
    @State private var showingShareSheet = false
    @State private var showingSummarySheet = false

    private var activeParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .active }
    }

    private var completedParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .completed }
    }

    private var currentCallsign: String {
        // Try to get from keychain first
        if let callsign = try? KeychainHelper.shared.readString(for: KeychainHelper.Keys.currentCallsign),
           !callsign.isEmpty
        {
            return callsign
        }
        // Fall back to "Me" if not configured
        return "Me"
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
        itemToShare = item
        showingShareSheet = true
    }
}

// MARK: - ActivityView+Actions

extension ActivityView {
    func refresh() async {
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

            // Sync activity feed from server
            if let feedService = feedSyncService {
                try await feedService.syncFeed(sourceURL: "https://challenges.example.com")
            }
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    func handleInviteNotification(_ notification: Notification) {
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

    func evaluateNewQSOs() async {
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
