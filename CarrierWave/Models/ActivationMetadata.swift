//
//  ActivationMetadata.swift
//  CarrierWave
//

import Foundation
import SwiftData

/// Stores metadata for POTA activations (weather, solar conditions)
/// Keyed by park reference + date (UTC start of day)
@Model
final class ActivationMetadata {
    // MARK: Lifecycle

    init(parkReference: String, date: Date, weather: String? = nil, solarConditions: String? = nil) {
        self.parkReference = parkReference
        // Normalize to start of day in UTC
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.date = calendar.startOfDay(for: date)
        self.weather = weather
        self.solarConditions = solarConditions
    }

    // MARK: Internal

    // Default values required for SwiftData lightweight migration
    var parkReference = ""
    var date = Date()
    var weather: String?
    var solarConditions: String?
}
