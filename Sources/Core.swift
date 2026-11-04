import Foundation

struct ApocalypseEvent: Codable {
    let id: String
    let date: String
    let title: String
    let explanation: String
    let source: String
    let sourceURL: URL

    var target: Date { Self.parseDay(date)! }

    static func parseDay(_ value: String) -> Date? {
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
}

enum EventCatalog {
    static func load(_ url: URL) throws -> [ApocalypseEvent] {
        let events = try JSONDecoder().decode([ApocalypseEvent].self, from: Data(contentsOf: url))
        guard !events.isEmpty, Set(events.map(\.id)).count == events.count,
              events.allSatisfy({ ApocalypseEvent.parseDay($0.date) != nil &&
                  !$0.title.isEmpty && !$0.explanation.isEmpty && !$0.source.isEmpty &&
                  $0.sourceURL.scheme == "https" && $0.sourceURL.host != nil }) else {
            throw NSError(domain: "TEotW.Catalog", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось проверить даты и источники каталога."])
        }
        return events.sorted { $0.target < $1.target }
    }

    static func next(in events: [ApocalypseEvent], now: Date) -> ApocalypseEvent? {
        events.filter { $0.target > now }.min { $0.target < $1.target }
    }
}

enum Countdown {
    static func string(until target: Date, now: Date) -> String {
        let interval = max(0, ceil(target.timeIntervalSince(now)))
        guard interval.isFinite, interval < Double(Int.max / 2) else { return "00:00:00" }
        let seconds = Int(interval)
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}
