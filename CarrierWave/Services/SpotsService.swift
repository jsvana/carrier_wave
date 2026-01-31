// Combined spots service for RBN and POTA
//
// Fetches and merges spots from both RBN (Reverse Beacon Network) and
// POTA (Parks on the Air) into a unified format.

import Foundation

// MARK: - SpotSource

/// Source of a spot
enum SpotSource: Sendable {
    case rbn
    case pota
}

// MARK: - UnifiedSpot

/// A spot from either RBN or POTA in a unified format
struct UnifiedSpot: Identifiable, Sendable {
    let id: String
    let callsign: String
    let frequencyKHz: Double
    let mode: String
    let timestamp: Date
    let source: SpotSource

    // RBN-specific fields
    let snr: Int?
    let wpm: Int?
    let spotter: String?
    let spotterGrid: String?

    // POTA-specific fields
    let parkRef: String?
    let parkName: String?
    let comments: String?

    /// Frequency in MHz
    var frequencyMHz: Double {
        frequencyKHz / 1_000.0
    }

    /// Band derived from frequency
    var band: String {
        LoggingSession.bandForFrequency(frequencyMHz)
    }

    /// Formatted frequency string
    var formattedFrequency: String {
        String(format: "%.1f kHz", frequencyKHz)
    }

    /// Time ago string
    var timeAgo: String {
        let seconds = Date().timeIntervalSince(timestamp)
        if seconds < 60 {
            return "\(Int(seconds))s ago"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m ago"
        } else {
            return "\(Int(seconds / 3_600))h ago"
        }
    }
}

// MARK: - SpotsService

/// Service for fetching combined spots from RBN and POTA
actor SpotsService {
    // MARK: Lifecycle

    /// Initialize with pre-created clients from a @MainActor context
    init(rbnClient: RBNClient, potaClient: POTAClient) {
        self.rbnClient = rbnClient
        self.potaClient = potaClient
    }

    // MARK: Internal

    /// Fetch combined spots for a callsign from both RBN and POTA
    /// - Parameters:
    ///   - callsign: The callsign to look up spots for
    ///   - hours: How many hours back to search (for RBN)
    /// - Returns: Combined and sorted list of spots
    func fetchSpots(for callsign: String, hours: Int = 6) async throws -> [UnifiedSpot] {
        // Fetch from both sources concurrently
        async let rbnSpots = fetchRBNSpots(for: callsign, hours: hours)
        async let potaSpots = fetchPOTASpots(for: callsign)

        // Combine results, handling errors gracefully
        var allSpots: [UnifiedSpot] = []

        do {
            try await allSpots.append(contentsOf: rbnSpots)
        } catch {
            // Log but don't fail if RBN is unavailable
            await SyncDebugLog.shared.warning(
                "RBN fetch failed: \(error.localizedDescription)",
                service: .pota
            )
        }

        do {
            try await allSpots.append(contentsOf: potaSpots)
        } catch {
            // Log but don't fail if POTA is unavailable
            await SyncDebugLog.shared.warning(
                "POTA spots fetch failed: \(error.localizedDescription)",
                service: .pota
            )
        }

        // Sort by timestamp, most recent first
        return allSpots.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: Private

    private let rbnClient: RBNClient
    private let potaClient: POTAClient

    private func fetchRBNSpots(for callsign: String, hours: Int) async throws -> [UnifiedSpot] {
        let spots = try await rbnClient.spots(for: callsign, hours: hours, limit: 50)
        return spots.map { spot in
            UnifiedSpot(
                id: "rbn-\(spot.id)",
                callsign: spot.callsign,
                frequencyKHz: spot.frequency,
                mode: spot.mode,
                timestamp: spot.timestamp,
                source: .rbn,
                snr: spot.snr,
                wpm: spot.wpm,
                spotter: spot.spotter,
                spotterGrid: spot.spotterGrid,
                parkRef: nil,
                parkName: nil,
                comments: nil
            )
        }
    }

    private func fetchPOTASpots(for callsign: String) async throws -> [UnifiedSpot] {
        let spots = try await potaClient.fetchSpots(for: callsign)
        return spots.compactMap { spot -> UnifiedSpot? in
            guard let freqKHz = spot.frequencyKHz,
                  let timestamp = spot.timestamp
            else {
                return nil
            }

            return UnifiedSpot(
                id: "pota-\(spot.spotId)",
                callsign: spot.activator,
                frequencyKHz: freqKHz,
                mode: spot.mode,
                timestamp: timestamp,
                source: .pota,
                snr: nil,
                wpm: nil,
                spotter: spot.spotter,
                spotterGrid: nil,
                parkRef: spot.reference,
                parkName: spot.parkName,
                comments: spot.comments
            )
        }
    }
}
