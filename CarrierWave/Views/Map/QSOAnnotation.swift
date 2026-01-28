import CoreLocation
import Foundation

// MARK: - QSOAnnotation

/// Represents a cluster of QSOs at a location for map display
struct QSOAnnotation: Identifiable, Hashable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let gridSquare: String
    let qsoCount: Int
    let callsigns: [String]
    let mostRecentDate: Date

    /// Display title showing grid and count
    var displayTitle: String {
        if qsoCount == 1, let callsign = callsigns.first {
            return callsign
        }
        return "\(gridSquare) (\(qsoCount))"
    }

    /// Subtitle showing sample callsigns
    var displaySubtitle: String? {
        if qsoCount == 1 {
            return gridSquare
        }
        let sample = callsigns.prefix(3).joined(separator: ", ")
        if qsoCount > 3 {
            return "\(sample), +\(qsoCount - 3) more"
        }
        return sample
    }

    // MARK: Hashable

    static func == (lhs: QSOAnnotation, rhs: QSOAnnotation) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - QSOArc

/// Represents an arc between user location and a contact
struct QSOArc: Identifiable {
    let id: String
    let from: CLLocationCoordinate2D
    let to: CLLocationCoordinate2D
    let callsign: String
}
