import Foundation

/// A nil zone follows system timezone changes rather than freezing the launch zone.
struct SceneClockModel: Codable, Equatable {
    var timeZoneID: String? = nil
    var showsSeconds = false
    var uses24Hour = true
}
