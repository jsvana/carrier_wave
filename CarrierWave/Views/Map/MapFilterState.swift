import Foundation

/// Filter state for the QSO map view
@Observable
final class MapFilterState {
    var startDate: Date?
    var endDate: Date?
    var selectedBand: String?
    var selectedMode: String?
    var selectedPark: String?
    var confirmedOnly: Bool = false
    var showArcs: Bool = false

    /// Check if any filter is active
    var hasActiveFilters: Bool {
        startDate != nil || endDate != nil || selectedBand != nil ||
            selectedMode != nil || selectedPark != nil || confirmedOnly
    }

    /// Reset all filters
    func resetFilters() {
        startDate = nil
        endDate = nil
        selectedBand = nil
        selectedMode = nil
        selectedPark = nil
        confirmedOnly = false
    }
}
