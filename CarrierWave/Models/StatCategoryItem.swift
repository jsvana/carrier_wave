import Foundation

struct StatCategoryItem: Identifiable {
    // MARK: Lifecycle

    init(identifier: String, description: String, qsos: [QSO]) {
        id = identifier
        self.identifier = identifier
        self.description = description
        count = qsos.count
        self.qsos = qsos.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: Internal

    let id: String
    let identifier: String
    let description: String
    let count: Int
    let qsos: [QSO]
}
