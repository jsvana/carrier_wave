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
        }
    }

    // MARK: Private

    @State private var isRefreshing = false

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

            // Placeholder - will embed challenge content
            Text("Challenge cards will appear here")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        isRefreshing = true
        defer { isRefreshing = false }

        // Placeholder: will refresh challenges and activity feed
        try? await Task.sleep(nanoseconds: 500_000_000)
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
