import Foundation

enum ImportSource: String, Codable {
    case lofi
    case adifFile
    case icloud
    case qrz
    case pota
}

enum ServiceType: String, Codable, CaseIterable {
    case qrz
    case pota
    case lofi

    var displayName: String {
        switch self {
        case .qrz: return "QRZ"
        case .pota: return "POTA"
        case .lofi: return "LoFi"
        }
    }

    var supportsUpload: Bool {
        switch self {
        case .qrz, .pota: return true
        case .lofi: return false
        }
    }

    /// Convert to ImportSource for comparison
    var toImportSource: ImportSource {
        switch self {
        case .qrz: return .qrz
        case .pota: return .pota
        case .lofi: return .lofi
        }
    }
}

// MARK: - String Helpers

extension Optional where Wrapped == String {
    /// Returns self if non-nil and non-empty, otherwise nil
    var nonEmpty: String? {
        guard let s = self, !s.isEmpty else { return nil }
        return s
    }
}
