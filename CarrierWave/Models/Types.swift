import Foundation

// MARK: - ImportSource

enum ImportSource: String, Codable {
    case lofi
    case adifFile
    case icloud
    case qrz
    case pota
    case hamrs
}

// MARK: - ServiceType

enum ServiceType: String, Codable, CaseIterable {
    case qrz
    case pota
    case lofi
    case hamrs

    // MARK: Internal

    var displayName: String {
        switch self {
        case .qrz: "QRZ"
        case .pota: "POTA"
        case .lofi: "LoFi"
        case .hamrs: "HAMRS"
        }
    }

    var supportsUpload: Bool {
        switch self {
        case .qrz,
             .pota: true
        case .lofi,
             .hamrs: false
        }
    }

    /// Convert to ImportSource for comparison
    var toImportSource: ImportSource {
        switch self {
        case .qrz: .qrz
        case .pota: .pota
        case .lofi: .lofi
        case .hamrs: .hamrs
        }
    }
}

// MARK: - String Helpers

extension String? {
    /// Returns self if non-nil and non-empty, otherwise nil
    var nonEmpty: String? {
        guard let value = self, !value.isEmpty else {
            return nil
        }
        return value
    }
}
