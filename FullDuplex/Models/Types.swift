import Foundation

enum ImportSource: String, Codable {
    case lofi
    case adifFile
    case icloud
    case qrz
}

enum SyncStatus: String, Codable {
    case pending
    case uploaded
    case failed
}

enum DestinationType: String, Codable, CaseIterable {
    case qrz
    case pota

    var displayName: String {
        switch self {
        case .qrz: return "QRZ"
        case .pota: return "POTA"
        }
    }
}
