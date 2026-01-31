import Foundation
import SwiftData

// MARK: - DeduplicationResult

struct DeduplicationResult {
    let duplicateGroupsFound: Int
    let qsosMerged: Int
    let qsosRemoved: Int
}

// MARK: - DeduplicationService

@MainActor
final class DeduplicationService {
    // MARK: Lifecycle

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: Internal

    /// Find and merge duplicate QSOs within the given time window
    func findAndMergeDuplicates(timeWindowMinutes: Int = 5) throws -> DeduplicationResult {
        // Fetch all QSOs sorted by timestamp
        let descriptor = FetchDescriptor<QSO>(sortBy: [SortDescriptor(\.timestamp)])
        let allQSOs = try modelContext.fetch(descriptor)

        if allQSOs.isEmpty {
            return DeduplicationResult(duplicateGroupsFound: 0, qsosMerged: 0, qsosRemoved: 0)
        }

        let timeWindow = TimeInterval(timeWindowMinutes * 60)
        var duplicateGroups: [[QSO]] = []
        var processed = Set<UUID>()

        // Find duplicate groups
        for i in 0 ..< allQSOs.count {
            let qso = allQSOs[i]
            if processed.contains(qso.id) {
                continue
            }

            var group = [qso]
            processed.insert(qso.id)

            // Check subsequent QSOs within time window
            for j in (i + 1) ..< allQSOs.count {
                let candidate = allQSOs[j]
                if processed.contains(candidate.id) {
                    continue
                }

                // Stop if beyond time window
                let timeDelta = candidate.timestamp.timeIntervalSince(qso.timestamp)
                if timeDelta > timeWindow {
                    break
                }

                // Check if duplicate (same call/band/mode within window)
                if isDuplicate(qso, candidate) {
                    group.append(candidate)
                    processed.insert(candidate.id)
                }
            }

            if group.count > 1 {
                duplicateGroups.append(group)
            }
        }

        // Merge each group
        var totalMerged = 0
        var totalRemoved = 0

        for group in duplicateGroups {
            let (merged, removed) = mergeGroup(group)
            totalMerged += merged
            totalRemoved += removed
        }

        try modelContext.save()

        return DeduplicationResult(
            duplicateGroupsFound: duplicateGroups.count,
            qsosMerged: totalMerged,
            qsosRemoved: totalRemoved
        )
    }

    // MARK: Private

    // MARK: - Mode Equivalence

    /// Generic mode names that should be replaced by specific modes when merging
    private static let genericModes: Set<String> = ["PHONE", "DATA"]

    /// Phone mode family - all considered equivalent for deduplication
    private static let phoneModes: Set<String> = ["PHONE", "SSB", "USB", "LSB", "AM", "FM", "DV"]

    /// Digital mode family - all considered equivalent for deduplication
    private static let digitalModes: Set<String> = [
        "DATA", "FT8", "FT4", "PSK31", "PSK", "RTTY", "JT65", "JT9", "MFSK", "OLIVIA",
    ]

    private let modelContext: ModelContext

    /// Check if two QSOs are duplicates (same callsign, mode, park reference, and optionally band)
    /// When either QSO has no band (empty string), matches on callsign+mode+time only.
    /// This handles POTA.app QSOs which don't include frequency/band info.
    /// Park reference (your activation park) must match - different activations are not duplicates.
    private func isDuplicate(_ qso1: QSO, _ qso2: QSO) -> Bool {
        let callsignMatch = qso1.callsign.uppercased() == qso2.callsign.uppercased()
        let modeMatch = modesAreEquivalent(qso1.mode, qso2.mode)

        guard callsignMatch && modeMatch else {
            return false
        }

        // Park reference (your activation park) must match
        // nil/nil = match, value/value = must match, nil/value = no match
        let park1 = qso1.parkReference?.trimmingCharacters(in: .whitespaces).uppercased()
        let park2 = qso2.parkReference?.trimmingCharacters(in: .whitespaces).uppercased()

        // Normalize empty strings to nil for comparison
        let normalizedPark1 = (park1?.isEmpty ?? true) ? nil : park1
        let normalizedPark2 = (park2?.isEmpty ?? true) ? nil : park2

        if normalizedPark1 != normalizedPark2 {
            return false
        }

        // If either QSO has no band, consider it a match (band-agnostic)
        let band1 = qso1.band.trimmingCharacters(in: .whitespaces)
        let band2 = qso2.band.trimmingCharacters(in: .whitespaces)

        if band1.isEmpty || band2.isEmpty {
            return true
        }

        // Both have bands - require match
        return band1.uppercased() == band2.uppercased()
    }

    /// Merge a group of duplicates, keeping the best one
    /// Returns (merged count, removed count)
    private func mergeGroup(_ group: [QSO]) -> (Int, Int) {
        guard group.count > 1 else {
            return (0, 0)
        }

        // Sort to find winner:
        // 1. Most synced services
        // 2. Highest field richness score
        let sorted = group.sorted { first, second in
            if first.syncedServicesCount != second.syncedServicesCount {
                return first.syncedServicesCount > second.syncedServicesCount
            }
            return first.fieldRichnessScore > second.fieldRichnessScore
        }

        let winner = sorted[0]
        let losers = Array(sorted.dropFirst())

        // Absorb data from losers into winner
        for loser in losers {
            absorbFields(from: loser, into: winner)
            absorbServicePresence(from: loser, into: winner)
            modelContext.delete(loser)
        }

        return (1, losers.count)
    }

    /// Fill nil/empty fields in winner from loser
    private func absorbFields(from loser: QSO, into winner: QSO) {
        if winner.rstSent == nil {
            winner.rstSent = loser.rstSent
        }
        if winner.rstReceived == nil {
            winner.rstReceived = loser.rstReceived
        }
        if winner.myGrid == nil {
            winner.myGrid = loser.myGrid
        }
        if winner.theirGrid == nil {
            winner.theirGrid = loser.theirGrid
        }
        if winner.parkReference == nil {
            winner.parkReference = loser.parkReference
        }
        if winner.notes == nil {
            winner.notes = loser.notes
        }
        if winner.qrzLogId == nil {
            winner.qrzLogId = loser.qrzLogId
        }
        if winner.rawADIF == nil {
            winner.rawADIF = loser.rawADIF
        }
        if winner.frequency == nil {
            winner.frequency = loser.frequency
        }
        // Absorb band if winner has empty band (e.g., from POTA)
        let winnerBand = winner.band.trimmingCharacters(in: .whitespaces)
        let loserBand = loser.band.trimmingCharacters(in: .whitespaces)
        if winnerBand.isEmpty, !loserBand.isEmpty {
            winner.band = loser.band
        }
        // Prefer specific mode over generic (e.g., SSB over PHONE)
        winner.mode = moreSpecificMode(winner.mode, loser.mode)
    }

    /// Transfer service presence records from loser to winner
    private func absorbServicePresence(from loser: QSO, into winner: QSO) {
        for presence in loser.servicePresence {
            // Check if winner already has this service
            if let existing = winner.presence(for: presence.serviceType) {
                // Update if loser's is "better" (present beats not present)
                if presence.isPresent, !existing.isPresent {
                    existing.isPresent = true
                    existing.needsUpload = false
                    existing.lastConfirmedAt = presence.lastConfirmedAt
                }
            } else {
                // Transfer the presence record to winner
                presence.qso = winner
                winner.servicePresence.append(presence)
            }
        }
    }

    /// Check if two modes are equivalent (handles PHONE/SSB/USB/LSB aliases and digital modes)
    private func modesAreEquivalent(_ mode1: String, _ mode2: String) -> Bool {
        let m1 = mode1.uppercased()
        let m2 = mode2.uppercased()

        // Direct match
        if m1 == m2 {
            return true
        }

        // Check if both are in the same mode family
        if Self.phoneModes.contains(m1), Self.phoneModes.contains(m2) {
            return true
        }
        if Self.digitalModes.contains(m1), Self.digitalModes.contains(m2) {
            return true
        }

        return false
    }

    /// Returns the more specific of two equivalent modes (prefers SSB over PHONE, FT8 over DATA)
    private func moreSpecificMode(_ mode1: String, _ mode2: String) -> String {
        let m1 = mode1.uppercased()
        let m2 = mode2.uppercased()

        // If one is generic and the other isn't, prefer the specific one
        let m1IsGeneric = Self.genericModes.contains(m1)
        let m2IsGeneric = Self.genericModes.contains(m2)

        if m1IsGeneric, !m2IsGeneric {
            return mode2
        }
        if m2IsGeneric, !m1IsGeneric {
            return mode1
        }

        // Both specific or both generic - keep the first one
        return mode1
    }
}
