import Foundation

struct FavoriteFolder: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var order: Int

    init(id: UUID = UUID(), name: String, order: Int) {
        self.id = id
        self.name = name
        self.order = order
    }
}
