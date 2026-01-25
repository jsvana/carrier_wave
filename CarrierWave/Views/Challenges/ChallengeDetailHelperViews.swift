import SwiftData
import SwiftUI

// MARK: - ProgressRing

struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 8)

            Circle()
                .trim(from: 0, to: min(progress, 1))
                .stroke(
                    progress >= 1 ? Color.green : Color.accentColor,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut, value: progress)

            Text(String(format: "%.0f%%", progress * 100))
                .font(.headline)
        }
    }
}

// MARK: - LeaderboardEntryRow

struct LeaderboardEntryRow: View {
    // MARK: Internal

    let entry: LeaderboardEntry
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Rank
            Text("#\(entry.rank)")
                .font(compact ? .subheadline : .headline)
                .fontWeight(.bold)
                .foregroundStyle(rankColor)
                .frame(width: compact ? 30 : 40)

            // Callsign
            Text(entry.callsign)
                .font(compact ? .subheadline : .body)
                .fontWeight(entry.isCurrentUser ? .bold : .regular)

            if entry.isCurrentUser {
                Text("(You)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Score/Progress
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.score)")
                    .font(compact ? .subheadline : .body)
                    .fontWeight(.medium)

                if !compact {
                    Text(String(format: "%.1f%%", entry.progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, compact ? 4 : 8)
        .padding(.horizontal, compact ? 0 : 12)
        .background(entry.isCurrentUser ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var rankColor: Color {
        switch entry.rank {
        case 1: .yellow
        case 2: .gray
        case 3: .orange
        default: .primary
        }
    }
}

// MARK: - TierProgressView

struct TierProgressView: View {
    // MARK: Internal

    let tiers: [ChallengeTier]
    let participation: ChallengeParticipation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tiers")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(tiers) { tier in
                let isAchieved = isTierAchieved(tier)
                HStack {
                    Image(systemName: isAchieved ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isAchieved ? .green : .secondary)
                    Text(tier.name)
                        .font(.subheadline)
                        .foregroundStyle(isAchieved ? .primary : .secondary)
                    Spacer()
                    Text("\(tier.threshold)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Private

    private func isTierAchieved(_ tier: ChallengeTier) -> Bool {
        let currentValue =
            participation.challengeType == .collection
                ? participation.completedGoalsCount
                : participation.progress.currentValue
        return currentValue >= tier.threshold
    }
}

// MARK: - DrilldownRow

struct DrilldownRow: View {
    let icon: String
    let iconColor: Color
    let text: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            Text(text)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - GoalListView

struct GoalListView: View {
    // MARK: Internal

    let participation: ChallengeParticipation
    let showCompleted: Bool

    var goals: [ChallengeGoal] {
        guard let definition = participation.challengeDefinition else {
            return []
        }
        let completedIds = Set(participation.progress.completedGoals)

        return definition.goals.filter { goal in
            let isCompleted = completedIds.contains(goal.id)
            return showCompleted ? isCompleted : !isCompleted
        }
    }

    var filteredGoals: [ChallengeGoal] {
        if searchText.isEmpty {
            return goals
        }
        return goals.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            ForEach(filteredGoals) { goal in
                HStack {
                    VStack(alignment: .leading) {
                        Text(goal.name)
                            .font(.body)
                        Text(goal.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if showCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search goals")
        .navigationTitle(showCompleted ? "Completed" : "Remaining")
    }

    // MARK: Private

    @State private var searchText = ""
}

// MARK: - QualifyingQSOsView

struct QualifyingQSOsView: View {
    let participation: ChallengeParticipation

    @Query var allQSOs: [QSO]

    var qualifyingQSOs: [QSO] {
        let ids = Set(participation.progress.qualifyingQSOIds)
        return allQSOs.filter { ids.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        List {
            ForEach(qualifyingQSOs) { qso in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(qso.callsign)
                            .font(.headline)
                        Spacer()
                        Text(qso.timestamp, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text(qso.band)
                        Text(qso.mode)
                        if let state = qso.state {
                            Text(state)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Qualifying QSOs")
    }
}
