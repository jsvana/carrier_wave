import Foundation
import SwiftData

@Model
final class ServicePresence {
    // MARK: Lifecycle

    init(
        id: UUID = UUID(),
        serviceType: ServiceType,
        isPresent: Bool = false,
        needsUpload: Bool = false,
        lastConfirmedAt: Date? = nil,
        qso: QSO? = nil
    ) {
        self.id = id
        self.serviceType = serviceType
        self.isPresent = isPresent
        self.needsUpload = needsUpload
        self.lastConfirmedAt = lastConfirmedAt
        self.qso = qso
    }

    // MARK: Internal

    var id: UUID
    var serviceType: ServiceType
    var isPresent: Bool
    var needsUpload: Bool
    var lastConfirmedAt: Date?

    var qso: QSO?

    /// Create a presence record for a QSO that was downloaded from a service
    static func downloaded(from service: ServiceType, qso: QSO? = nil) -> ServicePresence {
        ServicePresence(
            serviceType: service,
            isPresent: true,
            needsUpload: false,
            lastConfirmedAt: Date(),
            qso: qso
        )
    }

    /// Create a presence record for a QSO that needs to be uploaded to a service
    static func needsUpload(to service: ServiceType, qso: QSO? = nil) -> ServicePresence {
        ServicePresence(
            serviceType: service,
            isPresent: false,
            needsUpload: service.supportsUpload,
            lastConfirmedAt: nil,
            qso: qso
        )
    }
}
