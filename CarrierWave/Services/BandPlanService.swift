// swiftlint:disable function_body_length identifier_name
// Band Plan Service
//
// Validates frequency and mode combinations against license class privileges.

import Foundation

// MARK: - BandPlanViolation

/// Describes a band plan violation
struct BandPlanViolation: Sendable {
    enum ViolationType: Sendable {
        case noPrivileges
        case wrongMode
        case outOfBand
        case unusualFrequency // Soft warning - not prohibited, just unusual
    }

    let type: ViolationType
    let message: String
    let suggestion: String?
}

// MARK: - BandPlanService

/// Service for validating frequency/mode against license class
enum BandPlanService {
    // MARK: Internal

    /// Check if a frequency/mode combination is valid for a license class
    /// - Parameters:
    ///   - frequencyMHz: Operating frequency in MHz
    ///   - mode: Operating mode (CW, SSB, etc.)
    ///   - license: User's license class
    /// - Returns: A violation if the operation is not allowed, nil if allowed
    static func validate(
        frequencyMHz: Double,
        mode: String,
        license: LicenseClass
    ) -> BandPlanViolation? {
        let normalizedMode = normalizeMode(mode)

        // Find all segments that contain this frequency
        let matchingSegments = BandPlan.segments.filter { $0.contains(frequencyMHz: frequencyMHz) }

        // If no segments match, frequency is out of band
        guard !matchingSegments.isEmpty else {
            return BandPlanViolation(
                type: .outOfBand,
                message:
                "Frequency \(String(format: "%.3f", frequencyMHz)) MHz is outside amateur bands",
                suggestion: suggestNearestBand(frequencyMHz: frequencyMHz)
            )
        }

        // Check for segments that allow this mode
        let modeSegments = matchingSegments.filter { $0.allowsMode(normalizedMode) }

        if modeSegments.isEmpty {
            // CW is allowed anywhere in amateur bands, but warn if unusual
            if normalizedMode == "CW" {
                let typicalModes = Set(matchingSegments.flatMap(\.modes))
                let typicalModesStr = typicalModes.sorted().joined(separator: ", ")
                return BandPlanViolation(
                    type: .unusualFrequency,
                    message:
                    "\(String(format: "%.3f", frequencyMHz)) MHz is not a typical CW frequency",
                    suggestion: "Usually \(typicalModesStr) here"
                )
            }

            // Mode not allowed at this frequency
            let allowedModes = Set(matchingSegments.flatMap(\.modes))
            return BandPlanViolation(
                type: .wrongMode,
                message: "\(mode) is not allowed at \(String(format: "%.3f", frequencyMHz)) MHz",
                suggestion: "Try: \(allowedModes.joined(separator: ", "))"
            )
        }

        // Check license class privileges
        let privilegeOrder: [LicenseClass] = [.technician, .general, .extra]
        let userPrivilegeIndex = privilegeOrder.firstIndex(of: license) ?? 0

        // Find segments where user has privileges
        let allowedSegments = modeSegments.filter { segment in
            let requiredIndex = privilegeOrder.firstIndex(of: segment.minimumLicense) ?? 0
            return userPrivilegeIndex >= requiredIndex
        }

        if allowedSegments.isEmpty {
            // User doesn't have privileges
            let requiredLicense =
                modeSegments
                    .map(\.minimumLicense)
                    .min { a, b in
                        (privilegeOrder.firstIndex(of: a) ?? 0)
                            < (privilegeOrder.firstIndex(of: b) ?? 0)
                    } ?? .extra

            let freqStr = String(format: "%.3f", frequencyMHz)
            return BandPlanViolation(
                type: .noPrivileges,
                message: "\(license.displayName) license cannot operate \(mode) at \(freqStr) MHz",
                suggestion: "Requires \(requiredLicense.displayName) or higher"
            )
        }

        return nil
    }

    /// Get the band name for a frequency
    static func bandFor(frequencyMHz: Double) -> String? {
        BandPlan.segments.first { $0.contains(frequencyMHz: frequencyMHz) }?.band
    }

    /// Get suggested frequencies for a mode and license
    static func suggestedFrequencies(
        mode: String,
        license: LicenseClass
    ) -> [(band: String, frequencyMHz: Double)] {
        let normalizedMode = normalizeMode(mode)

        if normalizedMode == "CW" {
            return BandPlan.cwCallingFrequencies
                .filter { validate(frequencyMHz: $0.value, mode: mode, license: license) == nil }
                .sorted { $0.value < $1.value }
                .map { ($0.key, $0.value) }
        } else if normalizedMode == "SSB" || normalizedMode == "PHONE" {
            return BandPlan.ssbCallingFrequencies
                .filter { validate(frequencyMHz: $0.value, mode: mode, license: license) == nil }
                .sorted { $0.value < $1.value }
                .map { ($0.key, $0.value) }
        }

        return []
    }

    /// Get all segments where a license class has privileges
    static func privilegedSegments(for license: LicenseClass) -> [BandSegment] {
        let privilegeOrder: [LicenseClass] = [.technician, .general, .extra]
        let userPrivilegeIndex = privilegeOrder.firstIndex(of: license) ?? 0

        return BandPlan.segments.filter { segment in
            let requiredIndex = privilegeOrder.firstIndex(of: segment.minimumLicense) ?? 0
            return userPrivilegeIndex >= requiredIndex
        }
    }

    // MARK: Private

    private static func normalizeMode(_ mode: String) -> String {
        let upper = mode.uppercased()

        // Map common mode variants
        switch upper {
        case "LSB",
             "USB",
             "AM",
             "FM":
            return "PHONE"
        case "RTTY",
             "PSK",
             "FT8",
             "FT4",
             "JS8",
             "WSPR",
             "JT65",
             "JT9":
            return "DATA"
        default: return upper
        }
    }

    private static func suggestNearestBand(frequencyMHz: Double) -> String? {
        // Find the nearest band edge
        var nearestBand: String?
        var nearestDistance = Double.infinity

        for segment in BandPlan.segments {
            let distanceToStart = abs(frequencyMHz - segment.startMHz)
            let distanceToEnd = abs(frequencyMHz - segment.endMHz)
            let minDistance = min(distanceToStart, distanceToEnd)

            if minDistance < nearestDistance {
                nearestDistance = minDistance
                nearestBand = segment.band
            }
        }

        if let band = nearestBand, nearestDistance < 1.0 {
            return "Nearest band: \(band)"
        }

        return nil
    }
}
