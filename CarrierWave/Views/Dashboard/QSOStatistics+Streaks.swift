import Foundation

// MARK: - QSOStatistics Streak Extensions

extension QSOStatistics {
    /// Daily QSO streak (local timezone)
    var dailyStreak: StreakInfo {
        let activeDates = Set(qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
            .map(\.dateOnly))
        let result = StreakCalculator.calculateStreak(from: activeDates)
        return makeStreakInfo(id: "daily", category: .daily, result: result)
    }

    /// POTA activation streak (UTC dates, 10+ QSOs per activation)
    var potaActivationStreak: StreakInfo {
        let parksOnly = qsos.filter {
            !Self.metadataModes.contains($0.mode.uppercased()) &&
                $0.parkReference != nil && !$0.parkReference!.isEmpty
        }
        let grouped = Dictionary(grouping: parksOnly) { qso in
            "\(qso.parkReference!)|\(qso.utcDateOnly.timeIntervalSince1970)"
        }
        let validDates = Set(grouped.compactMap { _, qsos -> Date? in
            guard qsos.count >= 10, let first = qsos.first else {
                return nil
            }
            return first.utcDateOnly
        })
        let result = StreakCalculator.calculateStreak(from: validDates, useUTC: true)
        return makeStreakInfo(id: "pota", category: .pota, result: result)
    }

    /// All mode streaks sorted by current streak length
    var modeStreaks: [StreakInfo] {
        let realQSOs = qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
        let modes = Set(realQSOs.map { $0.mode.uppercased() })
        return modes.map { mode in
            let dates = Set(realQSOs.filter { $0.mode.uppercased() == mode }.map(\.dateOnly))
            let result = StreakCalculator.calculateStreak(from: dates)
            return makeStreakInfo(id: "mode-\(mode)", category: .mode, subcategory: mode, result: result)
        }.sorted { $0.currentStreak > $1.currentStreak }
    }

    /// All band streaks sorted by current streak length
    var bandStreaks: [StreakInfo] {
        let realQSOs = qsos.filter { !Self.metadataModes.contains($0.mode.uppercased()) }
        let bands = Set(realQSOs.map { $0.band.lowercased() })
        return bands.map { band in
            let dates = Set(realQSOs.filter { $0.band.lowercased() == band }.map(\.dateOnly))
            let result = StreakCalculator.calculateStreak(from: dates)
            return makeStreakInfo(id: "band-\(band)", category: .band, subcategory: band, result: result)
        }.sorted { $0.currentStreak > $1.currentStreak }
    }

    private static let metadataModes: Set<String> = ["WEATHER", "SOLAR", "NOTE"]

    private func makeStreakInfo(
        id: String, category: StreakCategory, subcategory: String? = nil, result: StreakResult
    ) -> StreakInfo {
        StreakInfo(
            id: id, category: category, subcategory: subcategory,
            currentStreak: result.current, longestStreak: result.longest,
            currentStartDate: result.currentStart, longestStartDate: result.longestStart,
            longestEndDate: result.longestEnd, lastActiveDate: result.lastActive
        )
    }
}
