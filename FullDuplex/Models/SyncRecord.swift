import Foundation
import SwiftData

@Model
final class SyncRecord {
    var id: UUID
    var destinationType: DestinationType
    var status: SyncStatus
    var uploadedAt: Date?
    var errorMessage: String?

    var qso: QSO?

    init(
        id: UUID = UUID(),
        destinationType: DestinationType,
        status: SyncStatus = .pending,
        uploadedAt: Date? = nil,
        errorMessage: String? = nil,
        qso: QSO? = nil
    ) {
        self.id = id
        self.destinationType = destinationType
        self.status = status
        self.uploadedAt = uploadedAt
        self.errorMessage = errorMessage
        self.qso = qso
    }
}
