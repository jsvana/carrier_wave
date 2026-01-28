import SwiftData
import SwiftUI

// MARK: - QSOStatistics

struct QSOStatistics {
    // MARK: Internal

    let qsos: [QSO]

    var totalQSOs: Int { realQSOs.count }

    var uniqueEntities: Int {
        Set(realQSOs.compactMap { $0.dxccEntity?.number }).count
    }

    var uniqueGrids: Int {
        Set(realQSOs.compactMap(\.theirGrid).filter { !$0.isEmpty }).count
    }

    var uniqueBands: Int {
        Set(realQSOs.map { $0.band.lowercased() }).count
    }

    var confirmedQSLs: Int {
        realQSOs.filter(\.lotwConfirmed).count
    }

    var uniqueParks: Int {
        Set(realQSOs.compactMap(\.parkReference).filter { !$0.isEmpty }).count
    }

    /// Activations with 10+ QSOs (valid POTA activations)
    /// Each activation is a unique park+UTC date combination
    var successfulActivations: Int {
        // Filter to QSOs with park references (realQSOs already excludes metadata)
        let parksOnly = realQSOs.filter {
            $0.parkReference != nil && !$0.parkReference!.isEmpty
        }
        // Group by park + UTC date (each UTC day at a park is a separate activation)
        let grouped = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        return grouped.values.filter { $0.count >= 10 }.count
    }

    /// Activations with <10 QSOs (activation attempts)
    /// Each activation is a unique park+UTC date combination
    var attemptedActivations: Int {
        // Filter to QSOs with park references (realQSOs already excludes metadata)
        let parksOnly = realQSOs.filter {
            $0.parkReference != nil && !$0.parkReference!.isEmpty
        }
        // Group by park + UTC date (each UTC day at a park is a separate activation)
        let grouped = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        return grouped.values.filter { $0.count < 10 }.count
    }

    var activityByDate: [Date: Int] {
        var activity: [Date: Int] = [:]
        for qso in realQSOs {
            let date = qso.dateOnly
            activity[date, default: 0] += 1
        }
        return activity
    }

    // MARK: - Streak Calculations

    func items(for category: StatCategoryType) -> [StatCategoryItem] {
        switch category {
        case .qsls:
            groupedByQSL()
        case .entities:
            groupedByEntity()
        case .grids:
            groupedByGrid()
        case .bands:
            groupedByBand()
        case .parks:
            groupedByPark()
        }
    }

    // MARK: Private

    /// Modes that represent activation metadata, not actual QSOs (from Ham2K PoLo)
    /// These should never be counted as QSOs for any statistics
    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    /// QSOs filtered to exclude metadata modes - use this for all stat calculations
    private var realQSOs: [QSO] {
        qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
    }

    private func groupedByEntity() -> [StatCategoryItem] {
        // Group by DXCC entity number (realQSOs excludes metadata)
        let withEntity = realQSOs.filter { $0.dxccEntity != nil }
        let grouped = Dictionary(grouping: withEntity) { $0.dxccEntity!.number }
        return grouped.map { entityNumber, qsos in
            let entity = qsos.first?.dxccEntity
            return StatCategoryItem(
                identifier: entity?.name ?? "Unknown",
                description: "DXCC #\(entityNumber)",
                qsos: qsos
            )
        }
    }

    private func groupedByGrid() -> [StatCategoryItem] {
        let gridsOnly = realQSOs.filter { $0.theirGrid != nil && !$0.theirGrid!.isEmpty }
        let grouped = Dictionary(grouping: gridsOnly) { $0.theirGrid! }
        return grouped.map { grid, qsos in
            StatCategoryItem(
                identifier: grid,
                description: DescriptionLookup.gridDescription(for: grid),
                qsos: qsos
            )
        }
    }

    private func groupedByBand() -> [StatCategoryItem] {
        let grouped = Dictionary(grouping: realQSOs) { $0.band.lowercased() }
        return grouped.map { band, qsos in
            StatCategoryItem(
                identifier: band,
                description: DescriptionLookup.bandDescription(for: band),
                qsos: qsos
            )
        }
    }

    private func groupedByQSL() -> [StatCategoryItem] {
        let confirmed = realQSOs.filter(\.lotwConfirmed)
        // Group by DXCC entity for confirmed QSLs
        let withEntity = confirmed.filter { $0.dxccEntity != nil }
        let grouped = Dictionary(grouping: withEntity) { $0.dxccEntity!.number }
        return grouped.map { entityNumber, qsos in
            let entity = qsos.first?.dxccEntity
            return StatCategoryItem(
                identifier: entity?.name ?? "Unknown",
                description: "DXCC #\(entityNumber) - \(qsos.count) confirmed",
                qsos: qsos
            )
        }
    }

    private func groupedByPark() -> [StatCategoryItem] {
        // Filter to QSOs with park references (realQSOs already excludes metadata)
        let parksOnly = realQSOs.filter {
            $0.parkReference != nil && !$0.parkReference!.isEmpty
        }
        // Group by park + UTC date (each UTC day at a park is a separate activation)
        let grouped = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        return grouped.map { _, qsos in
            let park = qsos.first?.parkReference ?? "Unknown"
            let date = qsos.first?.utcDateOnly ?? Date()
            let status = qsos.count >= 10 ? "Valid" : "\(qsos.count)/10 QSOs"
            return StatCategoryItem(
                identifier: "\(park) - \(dateFormatter.string(from: date))",
                description: status,
                qsos: qsos,
                date: date,
                parkReference: park
            )
        }
    }
}

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
            let cellSize = (gridWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let gridHeight = CGFloat(rows) * cellSize + CGFloat(rows - 1) * spacing
            let columnWidth = cellSize + spacing

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0 ..< columns, id: \.self) { column in
                        VStack(spacing: spacing) {
                            ForEach(0 ..< rows, id: \.self) { row in
                                let date = dateFor(column: column, row: row)
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
                    ForEach(monthLabelPositions, id: \.column) { item in
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
        .accessibilityLabel("Activity grid showing QSOs over the past \(columns) weeks")
    }

    // MARK: Private

    @State private var selectedDate: Date?

    private let columns = 26
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

    private var monthLabelPositions: [(column: Int, label: String)] {
        var labels: [(Int, String)] = []
        var lastMonth = -1

        for column in 0 ..< columns {
            let date = dateFor(column: column, row: 0)
            let month = calendar.component(.month, from: date)

            if month != lastMonth {
                labels.append((column, monthFormatter.string(from: date)))
                lastMonth = month
            }
        }
        return labels
    }

    private func dateFor(column: Int, row: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        let weeksBack = columns - 1 - column
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
