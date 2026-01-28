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
        case .frequencies:
            groupedByFrequency()
        case .bestFriends:
            groupedByPartner()
        case .bestHunters:
            groupedByHunter()
        }
    }

    /// Top frequencies used, grouped to nearest 100kHz
    func topFrequencies(limit: Int = 5) -> [StatCategoryItem] {
        Array(groupedByFrequency().sorted { $0.count > $1.count }.prefix(limit))
    }

    /// Top QSO partners (most frequent callsigns contacted)
    func topFriends(limit: Int = 5) -> [StatCategoryItem] {
        Array(groupedByPartner().sorted { $0.count > $1.count }.prefix(limit))
    }

    /// Top hunters (most frequent callers during POTA activations)
    func topHunters(limit: Int = 5) -> [StatCategoryItem] {
        Array(groupedByHunter().sorted { $0.count > $1.count }.prefix(limit))
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

    /// Group QSOs by frequency rounded to nearest 100Hz
    private func groupedByFrequency() -> [StatCategoryItem] {
        // Filter to QSOs with frequency data
        let withFrequency = realQSOs.filter { $0.frequency != nil && $0.frequency! > 0 }
        // Group by frequency rounded to nearest 100Hz (0.0001 MHz)
        let grouped = Dictionary(grouping: withFrequency) { qso in
            let freqMHz = qso.frequency! // Already in MHz
            let rounded = (freqMHz * 10_000).rounded() / 10_000 // Round to 0.0001 MHz = 100 Hz
            return rounded
        }
        return grouped.map { freqMHz, qsos in
            // Only show 100Hz digit if non-zero (e.g., 14.060 vs 14.0625)
            let has100Hz = (freqMHz * 10_000).truncatingRemainder(dividingBy: 10) != 0
            let freqString = String(format: has100Hz ? "%.4f MHz" : "%.3f MHz", freqMHz)
            let band = qsos.first?.band ?? "Unknown"
            return StatCategoryItem(
                identifier: freqString,
                description: band,
                qsos: qsos
            )
        }
    }

    /// Group QSOs by callsign (contact partner)
    private func groupedByPartner() -> [StatCategoryItem] {
        let grouped = Dictionary(grouping: realQSOs) { $0.callsign.uppercased() }
        return grouped.map { callsign, qsos in
            let entity = qsos.first?.dxccEntity?.name
            let description = entity ?? ""
            return StatCategoryItem(
                identifier: callsign,
                description: description,
                qsos: qsos
            )
        }
    }

    /// Group QSOs by callsign where I was activating (had a park reference)
    /// These are "hunters" who contacted me during POTA activations
    private func groupedByHunter() -> [StatCategoryItem] {
        // Filter to QSOs where I was activating (I have a park reference)
        let activationQSOs = realQSOs.filter {
            $0.parkReference != nil && !$0.parkReference!.isEmpty
        }
        let grouped = Dictionary(grouping: activationQSOs) { $0.callsign.uppercased() }
        return grouped.map { callsign, qsos in
            let entity = qsos.first?.dxccEntity?.name
            let description = entity ?? ""
            return StatCategoryItem(
                identifier: callsign,
                description: description,
                qsos: qsos
            )
        }
    }
}
