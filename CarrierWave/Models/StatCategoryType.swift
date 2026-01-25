import Foundation

enum StatCategoryType: String, CaseIterable, Identifiable {
    case entities
    case grids
    case bands
    case modes
    case parks

    // MARK: Internal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .entities: "DXCC Entities"
        case .grids: "Grids"
        case .bands: "Bands"
        case .modes: "Modes"
        case .parks: "Activations"
        }
    }

    var icon: String {
        switch self {
        case .entities: "globe"
        case .grids: "square.grid.3x3"
        case .bands: "waveform"
        case .modes: "dot.radiowaves.right"
        case .parks: "leaf"
        }
    }
}
