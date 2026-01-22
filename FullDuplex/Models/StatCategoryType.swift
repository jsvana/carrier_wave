import Foundation

enum StatCategoryType: String, CaseIterable, Identifiable {
    case entities
    case grids
    case bands
    case modes
    case parks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .entities: return "DXCC Entities"
        case .grids: return "Grids"
        case .bands: return "Bands"
        case .modes: return "Modes"
        case .parks: return "Activations"
        }
    }

    var icon: String {
        switch self {
        case .entities: return "globe"
        case .grids: return "square.grid.3x3"
        case .bands: return "waveform"
        case .modes: return "dot.radiowaves.right"
        case .parks: return "leaf"
        }
    }
}
