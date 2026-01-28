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
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { showingError = false }
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }

    // MARK: Private

    @State private var isRefreshing = false

    @Query(sort: \ChallengeParticipation.joinedAt, order: .reverse)
    private var allParticipations: [ChallengeParticipation]

    @State private var syncService: ChallengesSyncService?
    @State private var errorMessage: String?
    @State private var showingError = false

    private var activeParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .active }
    }

    private var completedParticipations: [ChallengeParticipation] {
        allParticipations.filter { $0.status == .completed }
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

            // Placeholder for feed
            ContentUnavailableView(
                "No Activity Yet",
                systemImage: "person.2",
                description: Text("Activity from friends and clubs will appear here.")
            )
        }
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
}

#Preview {
    ActivityView(tourState: TourState())
        .modelContainer(
            for: [
                ChallengeSource.self,
                ChallengeDefinition.self,
                ChallengeParticipation.self,
            ], inMemory: true
        )
}
