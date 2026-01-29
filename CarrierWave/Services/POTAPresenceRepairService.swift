import Foundation
import SwiftData

/// Service to detect and repair incorrectly marked POTA service presence records.
/// Prior to the fix, QSOs without park references were incorrectly marked as needing
/// upload to POTA. This service finds and optionally fixes those records.
@MainActor
class POTAPresenceRepairService {
    // MARK: Lifecycle

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: Internal

    struct RepairResult {
        let mismarkedCount: Int
        let repairedCount: Int
    }

    let modelContext: ModelContext

    /// Count QSOs that are incorrectly marked for POTA upload (no park reference but needsUpload=true)
    func countMismarkedQSOs() throws -> Int {
        let descriptor = FetchDescriptor<ServicePresence>()
        let allPresence = try modelContext.fetch(descriptor)

        var mismarkedCount = 0
        for presence in allPresence {
            guard presence.serviceType == .pota, presence.needsUpload else {
                continue
            }
            guard let qso = presence.qso else {
                continue
            }
            if qso.parkReference?.isEmpty ?? true {
                mismarkedCount += 1
            }
        }

        return mismarkedCount
    }

    /// Repair mismarked POTA service presence records by setting needsUpload=false
    /// for QSOs that don't have a park reference.
    func repairMismarkedQSOs() throws -> RepairResult {
        let descriptor = FetchDescriptor<ServicePresence>()
        let allPresence = try modelContext.fetch(descriptor)

        var mismarkedCount = 0
        var repairedCount = 0

        for presence in allPresence {
            guard presence.serviceType == .pota, presence.needsUpload else {
                continue
            }
            guard let qso = presence.qso else {
                continue
            }
            if qso.parkReference?.isEmpty ?? true {
                mismarkedCount += 1
                presence.needsUpload = false
                repairedCount += 1
            }
        }

        if repairedCount > 0 {
            try modelContext.save()
        }

        return RepairResult(mismarkedCount: mismarkedCount, repairedCount: repairedCount)
    }
}
