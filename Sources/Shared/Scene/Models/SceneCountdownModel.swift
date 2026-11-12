import Foundation

enum SceneCountdownSource: String, Codable { case custom, apocalypse }
enum SceneCountdownFormat: String, Codable { case daysAndTime, totalHours, days }

/// The custom deadline is retained even while the catalog preset is selected.
struct SceneCountdownModel: Codable, Equatable {
    var source: SceneCountdownSource = .custom
    var targetDate: Date
    var timeZoneID: String
    var format: SceneCountdownFormat = .daysAndTime
    var showsSeconds: Bool = true

    init(source: SceneCountdownSource = .custom, targetDate: Date = Date().addingTimeInterval(86400),
         timeZoneID: String = TimeZone.current.identifier, format: SceneCountdownFormat = .daysAndTime,
         showsSeconds: Bool = true) {
        self.source = source; self.targetDate = targetDate; self.timeZoneID = timeZoneID
        self.format = format; self.showsSeconds = showsSeconds
    }
}
