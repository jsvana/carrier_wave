import Foundation
import SwiftData

@Model
final class QSO {
    var id: UUID
    var callsign: String
    var band: String
    var mode: String
    var frequency: Double?
    var timestamp: Date
    var rstSent: String?
    var rstReceived: String?
    var myCallsign: String
    var myGrid: String?
    var theirGrid: String?
    var parkReference: String?
    var notes: String?
    var importSource: ImportSource
    var importedAt: Date
    var rawADIF: String?

    // QRZ sync tracking
    var qrzLogId: String?
    var qrzConfirmed: Bool = false
    var lotwConfirmedDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \ServicePresence.qso)
    var servicePresence: [ServicePresence] = []

    init(
        id: UUID = UUID(),
        callsign: String,
        band: String,
        mode: String,
        frequency: Double? = nil,
        timestamp: Date,
        rstSent: String? = nil,
        rstReceived: String? = nil,
        myCallsign: String,
        myGrid: String? = nil,
        theirGrid: String? = nil,
        parkReference: String? = nil,
        notes: String? = nil,
        importSource: ImportSource,
        importedAt: Date = Date(),
        rawADIF: String? = nil,
        qrzLogId: String? = nil,
        qrzConfirmed: Bool = false,
        lotwConfirmedDate: Date? = nil
    ) {
        self.id = id
        self.callsign = callsign
        self.band = band
        self.mode = mode
        self.frequency = frequency
        self.timestamp = timestamp
        self.rstSent = rstSent
        self.rstReceived = rstReceived
        self.myCallsign = myCallsign
        self.myGrid = myGrid
        self.theirGrid = theirGrid
        self.parkReference = parkReference
        self.notes = notes
        self.importSource = importSource
        self.importedAt = importedAt
        self.rawADIF = rawADIF
        self.qrzLogId = qrzLogId
        self.qrzConfirmed = qrzConfirmed
        self.lotwConfirmedDate = lotwConfirmedDate
    }

    /// Deduplication key: callsign + band + mode + timestamp (rounded to 2 min)
    var deduplicationKey: String {
        let roundedTimestamp = timestamp.timeIntervalSince1970
        let rounded = Int(roundedTimestamp / 120) * 120 // 2 minute buckets
        return "\(callsign.uppercased())|\(band.uppercased())|\(mode.uppercased())|\(rounded)"
    }

    /// Extract callsign prefix (approximate DXCC entity)
    var callsignPrefix: String {
        let upper = callsign.uppercased()
        // Simple prefix extraction - takes letters/numbers before any /
        let base = upper.components(separatedBy: "/").first ?? upper
        // Extract prefix (first 1-3 chars that form entity)
        var prefix = ""
        for char in base {
            if char.isLetter || char.isNumber {
                prefix.append(char)
                // Most prefixes are 1-3 characters
                if prefix.count >= 2 && char.isNumber {
                    break
                }
                if prefix.count >= 3 {
                    break
                }
            }
        }
        return prefix
    }

    /// Check if this is likely a US station (for state counting)
    var isUSStation: Bool {
        let prefix = callsignPrefix
        return prefix.hasPrefix("K") || prefix.hasPrefix("W") || prefix.hasPrefix("N") || prefix.hasPrefix("A")
    }

    /// Count of populated optional fields (for deduplication tiebreaker)
    var fieldRichnessScore: Int {
        var score = 0
        if rstSent != nil { score += 1 }
        if rstReceived != nil { score += 1 }
        if myGrid != nil { score += 1 }
        if theirGrid != nil { score += 1 }
        if parkReference != nil { score += 1 }
        if notes != nil { score += 1 }
        if qrzLogId != nil { score += 1 }
        if rawADIF != nil { score += 1 }
        if frequency != nil { score += 1 }
        return score
    }

    /// Count of services where this QSO is confirmed present
    var syncedServicesCount: Int {
        servicePresence.filter { $0.isPresent }.count
    }

    /// Date only (for activity tracking)
    var dateOnly: Date {
        Calendar.current.startOfDay(for: timestamp)
    }

    // MARK: - Service Presence Helpers

    /// Get presence record for a specific service
    func presence(for service: ServiceType) -> ServicePresence? {
        servicePresence.first { $0.serviceType == service }
    }

    /// Check if QSO is present in a service
    func isPresent(in service: ServiceType) -> Bool {
        presence(for: service)?.isPresent ?? false
    }

    /// Check if QSO needs upload to a service
    func needsUpload(to service: ServiceType) -> Bool {
        presence(for: service)?.needsUpload ?? false
    }

    /// Mark QSO as present in a service
    func markPresent(in service: ServiceType, context: ModelContext) {
        if let existing = presence(for: service) {
            existing.isPresent = true
            existing.needsUpload = false
            existing.lastConfirmedAt = Date()
        } else {
            let newPresence = ServicePresence.downloaded(from: service, qso: self)
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }

    /// Mark QSO as needing upload to a service (if it supports upload)
    func markNeedsUpload(to service: ServiceType, context: ModelContext) {
        guard service.supportsUpload else { return }

        if let existing = presence(for: service) {
            if !existing.isPresent {
                existing.needsUpload = true
            }
        } else {
            let newPresence = ServicePresence.needsUpload(to: service, qso: self)
            context.insert(newPresence)
            servicePresence.append(newPresence)
        }
    }
}
