import Foundation

struct StatCategoryItem: Identifiable {
    let id: String
    let identifier: String
    let description: String
    let count: Int
    let qsos: [QSO]

    init(identifier: String, description: String, qsos: [QSO]) {
        self.id = identifier
        self.identifier = identifier
        self.description = description
        self.count = qsos.count
        self.qsos = qsos.sorted { $0.timestamp > $1.timestamp }
    }
}
