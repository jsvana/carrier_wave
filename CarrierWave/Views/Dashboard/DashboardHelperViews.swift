import SwiftUI

// MARK: - StatBox

struct StatBox: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - ActivationsStatBox

struct ActivationsStatBox: View {
    let successful: Int

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "leaf")
                .font(.title3)
                .foregroundStyle(.blue)
            Text("\(successful)")
                .font(.title2)
                .fontWeight(.bold)
            Text("Activations")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - StreakStatBox

struct StreakStatBox: View {
    // MARK: Lifecycle

    init(streak: StreakInfo, showLongest: Bool = false) {
        self.streak = streak
        self.showLongest = showLongest
    }

    // MARK: Internal

    let streak: StreakInfo
    let showLongest: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundStyle(streakColor)
                if streak.isAtRisk {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Text("\(showLongest ? streak.longestStreak : streak.currentStreak)")
                .font(.title2)
                .fontWeight(.bold)
            Text(showLongest ? "Best" : "Current")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Private

    private var streakColor: Color {
        if streak.currentStreak == 0 {
            .gray
        } else if streak.isAtRisk {
            .orange
        } else if streak.currentStreak >= streak.longestStreak, streak.currentStreak > 0 {
            .red // At or beating personal best
        } else {
            .orange
        }
    }
}

// MARK: - StreaksCard

struct StreaksCard: View {
    let dailyStreak: StreakInfo
    let potaStreak: StreakInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Streaks")
                    .font(.headline)
                Spacer()
                if dailyStreak.isAtRisk || potaStreak.isAtRisk {
                    Label("At Risk", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Daily QSOs")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        StreakStatBox(streak: dailyStreak)
                        StreakStatBox(streak: dailyStreak, showLongest: true)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("POTA Activations")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        StreakStatBox(streak: potaStreak)
                        StreakStatBox(streak: potaStreak, showLongest: true)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - ActivityGrid

struct ActivityGrid: View {
    // MARK: Internal

    let activityData: [Date: Int]

    var body: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 2
            let gridWidth = geometry.size.width
            // Target cell size of ~14pt, with minimum 26 weeks and maximum 52 weeks
            let targetCellSize: CGFloat = 14
            let calculatedColumns = Int((gridWidth + spacing) / (targetCellSize + spacing))
            let columnCount = min(max(calculatedColumns, 26), 52)
            let cellSize = (gridWidth - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)
            let gridHeight = CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
            let columnWidth = cellSize + spacing

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0 ..< columnCount, id: \.self) { column in
                        VStack(spacing: spacing) {
                            ForEach(0 ..< rows, id: \.self) { row in
                                let date = dateFor(
                                    column: column, row: row, totalColumns: columnCount
                                )
                                let count = activityData[date] ?? 0

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(colorFor(count: count))
                                    .frame(width: cellSize, height: cellSize)
                                    .accessibilityLabel(
                                        "\(tooltipDateFormatter.string(from: date)): "
                                            + "\(count) QSO\(count == 1 ? "" : "s")"
                                    )
                                    .accessibilityHint("Tap to show details")
                                    .onTapGesture {
                                        if selectedDate == date {
                                            selectedDate = nil
                                        } else {
                                            selectedDate = date
                                        }
                                    }
                                    .popover(
                                        isPresented: Binding(
                                            get: { selectedDate == date },
                                            set: {
                                                if !$0 {
                                                    selectedDate = nil
                                                }
                                            }
                                        ),
                                        arrowEdge: .top
                                    ) {
                                        VStack(spacing: 4) {
                                            Text(tooltipDateFormatter.string(from: date))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("\(count) QSO\(count == 1 ? "" : "s")")
                                                .font(.headline)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .presentationCompactAdaptation(.popover)
                                    }
                            }
                        }
                    }
                }
                .frame(height: gridHeight)

                ZStack(alignment: .topLeading) {
                    ForEach(monthLabelPositions(columnCount: columnCount), id: \.column) { item in
                        Text(item.label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(x: CGFloat(item.column) * columnWidth)
                    }
                }
                .frame(width: gridWidth, height: 14, alignment: .topLeading)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity grid showing QSO history")
    }

    // MARK: Private

    @State private var selectedDate: Date?

    private let rows = 7

    private let calendar = Calendar.current
    private let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()

    private var maxCount: Int {
        activityData.values.max() ?? 1
    }

    private func monthLabelPositions(columnCount: Int) -> [(column: Int, label: String)] {
        var labels: [(Int, String)] = []
        var lastMonth = -1

        for column in 0 ..< columnCount {
            let date = dateFor(column: column, row: 0, totalColumns: columnCount)
            let month = calendar.component(.month, from: date)

            if month != lastMonth {
                labels.append((column, monthFormatter.string(from: date)))
                lastMonth = month
            }
        }
        return labels
    }

    private func dateFor(column: Int, row: Int, totalColumns: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        let weeksBack = totalColumns - 1 - column
        let daysBack = weeksBack * 7 + (todayWeekday - 1 - row)
        return calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
    }

    private func colorFor(count: Int) -> Color {
        if count == 0 {
            return Color(.systemGray5)
        }
        let intensity = min(Double(count) / Double(max(maxCount, 1)), 1.0)
        return Color.green.opacity(0.3 + intensity * 0.7)
    }
}

// MARK: - FavoritesCard

struct FavoritesCard: View {
    let stats: QSOStatistics
    let tourState: TourState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Favorites")
                .font(.headline)

            VStack(spacing: 0) {
                // Top Frequency
                FavoriteRow(
                    title: "Top Frequency",
                    icon: "dial.medium.fill",
                    topItem: stats.topFrequencies(limit: 1).first,
                    category: .frequencies,
                    allItems: stats.items(for: .frequencies),
                    tourState: tourState
                )

                Divider()
                    .padding(.leading, 44)

                // Best Friend
                FavoriteRow(
                    title: "Best Friend",
                    icon: "person.2.fill",
                    topItem: stats.topFriends(limit: 1).first,
                    category: .bestFriends,
                    allItems: stats.items(for: .bestFriends),
                    tourState: tourState
                )

                Divider()
                    .padding(.leading, 44)

                // Best Hunter
                FavoriteRow(
                    title: "Best Hunter",
                    icon: "scope",
                    topItem: stats.topHunters(limit: 1).first,
                    category: .bestHunters,
                    allItems: stats.items(for: .bestHunters),
                    tourState: tourState
                )
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - FavoriteRow

private struct FavoriteRow: View {
    let title: String
    let icon: String
    let topItem: StatCategoryItem?
    let category: StatCategoryType
    let allItems: [StatCategoryItem]
    let tourState: TourState

    var body: some View {
        NavigationLink {
            StatDetailView(category: category, items: allItems, tourState: tourState)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let item = topItem {
                        Text(item.identifier)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else {
                        Text("No data yet")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if let item = topItem {
                    Text("\(item.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
