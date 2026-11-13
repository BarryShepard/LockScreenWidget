import Foundation

/// Ordered outer-to-inner ancestry travels with leaves, including clipboard copies.
struct SceneGroupMembership: Codable, Equatable {
    var id: UUID
    var name: String = "Группа"
}
