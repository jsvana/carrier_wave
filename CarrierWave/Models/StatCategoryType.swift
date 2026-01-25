import Foundation

enum StatCategoryType: String, CaseIterable, Identifiable {
    case qsls
    case entities
    case grids
    case bands
    case parks

    // MARK: Internal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qsls: "QSLs"
        case .entities: "DXCC Entities"
        case .grids: "Grids"
        case .bands: "Bands"
        case .parks: "Activations"
        }
    }

    var icon: String {
        switch self {
        case .qsls: "checkmark.seal"
        case .entities: "globe"
        case .grids: "square.grid.3x3"
        case .bands: "waveform"
        case .parks: "leaf"
        }
    }
}
