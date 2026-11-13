import Foundation

enum SceneClockPresentationController {
    static func value(_ clock: SceneClockModel, at now: Date, systemZone: TimeZone = .autoupdatingCurrent) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = clock.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? systemZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        let hour = parts.hour ?? 0
        let displayedHour = clock.uses24Hour ? hour : (hour % 12 == 0 ? 12 : hour % 12)
        let hours = clock.uses24Hour ? String(format: "%02d", displayedHour) : String(displayedHour)
        let seconds = clock.showsSeconds ? String(format: ":%02d", parts.second ?? 0) : ""
        let period = clock.uses24Hour ? "" : (hour < 12 ? " AM" : " PM")
        return hours + String(format: ":%02d", parts.minute ?? 0) + seconds + period
    }
}
