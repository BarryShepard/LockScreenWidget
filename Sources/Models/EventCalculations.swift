import Foundation

func parseEventDay(_ value: String) -> Date? {
    let componentsText = value.split(separator: "-", omittingEmptySubsequences: false)
    guard componentsText.map(\.count) == [4, 2, 2],
          componentsText.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
    let parts = componentsText.compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
    let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
    guard let result = calendar.date(from: components) else { return nil }
    let check = calendar.dateComponents([.year, .month, .day], from: result)
    guard check.year == parts[0], check.month == parts[1], check.day == parts[2] else { return nil }
    return result
}

func eventHasCountdown(_ event: ApocalypseEventModel) -> Bool {
    event.countdownEnabled ?? (parseEventDay(event.date) != nil)
}

func eventTarget(_ event: ApocalypseEventModel) -> Date {
    parseEventDay(event.date) ?? .distantFuture
}

func displayedEventDate(_ event: ApocalypseEventModel) -> String { event.dateLabel ?? event.date }

func selectNextEvent(in catalog: EventCatalogModel, now: Date) -> ApocalypseEventModel? {
    catalog.events.filter { eventHasCountdown($0) && eventTarget($0) > now }
        .min { eventTarget($0) < eventTarget($1) }
}

func calculateCountdown(until target: Date, now: Date) -> String {
    let interval = max(0, ceil(target.timeIntervalSince(now)))
    guard interval.isFinite, interval < Double(Int.max / 2) else { return "00:00:00" }
    let seconds = Int(interval)
    return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
}

func makeCountdownDisplay(event: ApocalypseEventModel?, now: Date) -> CountdownDisplayModel {
    guard let event else { return CountdownDisplayModel() }
    let usesCountdown = eventHasCountdown(event)
    let information = [event.explanation, event.caveat, event.reviewNote]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    return CountdownDisplayModel(title: event.title,
        counter: usesCountdown ? calculateCountdown(until: eventTarget(event), now: now) : displayedEventDate(event),
        information: information + "\n\n" + event.source, usesCountdown: usesCountdown)
}
