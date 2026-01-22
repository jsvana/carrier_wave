import Foundation
import SwiftData

struct DeduplicationResult {
    let duplicateGroupsFound: Int
    let qsosMerged: Int
    let qsosRemoved: Int
}

actor DeduplicationService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Find and merge duplicate QSOs within the given time window
    func findAndMergeDuplicates(timeWindowMinutes: Int = 5) async throws -> DeduplicationResult {
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
        for i in 0..<allQSOs.count {
            let qso = allQSOs[i]
            if processed.contains(qso.id) { continue }

            var group = [qso]
            processed.insert(qso.id)

            // Check subsequent QSOs within time window
            for j in (i + 1)..<allQSOs.count {
                let candidate = allQSOs[j]
                if processed.contains(candidate.id) { continue }

                // Stop if beyond time window
                let timeDelta = candidate.timestamp.timeIntervalSince(qso.timestamp)
                if timeDelta > timeWindow { break }

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

    /// Check if two QSOs are duplicates (same callsign, mode, and optionally band)
    /// When either QSO has no band (empty string), matches on callsign+mode+time only.
    /// This handles POTA.app QSOs which don't include frequency/band info.
    private func isDuplicate(_ a: QSO, _ b: QSO) -> Bool {
        let callsignMatch = a.callsign.uppercased() == b.callsign.uppercased()
        let modeMatch = a.mode.uppercased() == b.mode.uppercased()

        guard callsignMatch && modeMatch else { return false }

        // If either QSO has no band, consider it a match (band-agnostic)
        let aBand = a.band.trimmingCharacters(in: .whitespaces)
        let bBand = b.band.trimmingCharacters(in: .whitespaces)

        if aBand.isEmpty || bBand.isEmpty {
            return true
        }

        // Both have bands - require match
        return aBand.uppercased() == bBand.uppercased()
    }

    /// Merge a group of duplicates, keeping the best one
    /// Returns (merged count, removed count)
    private func mergeGroup(_ group: [QSO]) -> (Int, Int) {
        guard group.count > 1 else { return (0, 0) }

        // Sort to find winner:
        // 1. Most synced services
        // 2. Highest field richness score
        let sorted = group.sorted { a, b in
            if a.syncedServicesCount != b.syncedServicesCount {
                return a.syncedServicesCount > b.syncedServicesCount
            }
            return a.fieldRichnessScore > b.fieldRichnessScore
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
        if winner.rstSent == nil { winner.rstSent = loser.rstSent }
        if winner.rstReceived == nil { winner.rstReceived = loser.rstReceived }
        if winner.myGrid == nil { winner.myGrid = loser.myGrid }
        if winner.theirGrid == nil { winner.theirGrid = loser.theirGrid }
        if winner.parkReference == nil { winner.parkReference = loser.parkReference }
        if winner.notes == nil { winner.notes = loser.notes }
        if winner.qrzLogId == nil { winner.qrzLogId = loser.qrzLogId }
        if winner.rawADIF == nil { winner.rawADIF = loser.rawADIF }
        if winner.frequency == nil { winner.frequency = loser.frequency }
        // Absorb band if winner has empty band (e.g., from POTA)
        if winner.band.trimmingCharacters(in: .whitespaces).isEmpty &&
           !loser.band.trimmingCharacters(in: .whitespaces).isEmpty {
            winner.band = loser.band
        }
    }

    /// Transfer service presence records from loser to winner
    private func absorbServicePresence(from loser: QSO, into winner: QSO) {
        for presence in loser.servicePresence {
            // Check if winner already has this service
            if let existing = winner.presence(for: presence.serviceType) {
                // Update if loser's is "better" (present beats not present)
                if presence.isPresent && !existing.isPresent {
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
}
