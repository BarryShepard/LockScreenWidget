import Foundation

enum SceneWallTimeResolution: Equatable {
    case invalid, unique(Date), ambiguous(Date, Date)
}

/// Pure date calculation shared by the editor, inspector and lock presenter.
enum SceneCountdownPresentationController {
    // Public Foundation Gregorian calendars use the historical 1582 cutover.
    // Accept complete Gregorian years only; stored absolute targets remain valid.
    static func nextEvent(in catalog: EventCatalogModel, at now: Date) -> ApocalypseEventModel? {
        let eligible = catalog.events.filter {
            parseEventDay($0.date) != nil && eventHasCountdown($0)
        }
        return selectNextEvent(in: EventCatalogModel(events: eligible), now: now)
    }

    static func value(_ timer: SceneCountdownModel, catalog: EventCatalogModel, at now: Date) -> String {
        let target = timer.source == .custom ? timer.targetDate : nextEvent(in: catalog, at: now).map(eventTarget) ?? now
        let remaining = max(0, target.timeIntervalSince(now))
        // Clamp before integer conversion; even an extreme finite persisted Date is safe.
        let rounding: FloatingPointRoundingRule = timer.format != .days && timer.showsSeconds ? .up : .down
        let seconds = remaining.isNaN ? 0 : Int(min(Double(Int.max / 4), remaining).rounded(rounding))
        if timer.format == .days { return days(seconds / 86400) }
        func padded(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }
        let hours = timer.format == .totalHours ? seconds / 3600 : (seconds / 3600) % 24
        let clock = padded(hours) + ":" + padded((seconds / 60) % 60) + (timer.showsSeconds ? ":" + padded(seconds % 60) : "")
        return timer.format == .daysAndTime ? days(seconds / 86400) + " " + clock : clock
    }

    static func days(_ value: Int) -> String {
        let end = value % 100
        let word = (11...14).contains(end) ? "дней" : value % 10 == 1 ? "день" : (2...4).contains(value % 10) ? "дня" : "дней"
        return "\(value) \(word)"
    }

    static func wallFields(_ target: Date, zone: String) -> (date: String, time: String)? {
        guard let timeZone = TimeZone(identifier: zone),
              (-70_000_000_000...260_000_000_000).contains(target.timeIntervalSinceReferenceDate) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let c = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: target)
        guard c.era == 1, let year = c.year, (1583...9999).contains(year), let month = c.month, let day = c.day,
              let hour = c.hour, let minute = c.minute, let second = c.second else { return nil }
        return (String(format: "%04d-%02d-%02d", year, month, day), String(format: "%02d:%02d:%02d", hour, minute, second))
    }

    static func resolve(date: String, time: String, zone: String) -> SceneWallTimeResolution {
        func parts(_ value: String, separator: Character, lengths: [Int]) -> [Int]? {
            let strings = value.split(separator: separator, omittingEmptySubsequences: false)
            guard strings.map(\.count) == lengths, strings.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
            return strings.compactMap { Int($0) }
        }
        guard let d = parts(date, separator: "-", lengths: [4,2,2]),
              let t = parts(time, separator: ":", lengths: time.count == 5 ? [2,2] : [2,2,2]),
              (1583...9999).contains(d[0]), (1...12).contains(d[1]), (1...31).contains(d[2]),
              (0...23).contains(t[0]), (0...59).contains(t[1]), (t.count == 2 || (0...59).contains(t[2])),
              let timeZone = TimeZone(identifier: zone) else { return .invalid }
        let components = DateComponents(era: 1, year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1], second: t.count == 3 ? t[2] : 0)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let neutral = utc.date(from: components), utc.dateComponents([.era,.year,.month,.day,.hour,.minute,.second], from: neutral) == components else { return .invalid }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        // Foundation's repeatedTimePolicy can return the same result for both
        // policies on half-hour folds (Lord Howe). Derive candidates from the
        // zone's actual nearby UTC offsets, then require an exact round trip.
        // The window also covers date-line shifts and historical second offsets.
        let offsets = Set((-48...48).map { hour in
            timeZone.secondsFromGMT(for: neutral.addingTimeInterval(Double(hour) * 3600))
        })
        let candidates = offsets.compactMap { offset -> Date? in
            let candidate = neutral.addingTimeInterval(-Double(offset))
            return calendar.dateComponents([.era,.year,.month,.day,.hour,.minute,.second], from: candidate) == components ? candidate : nil
        }.sorted()
        guard let first = candidates.first, let last = candidates.last else { return .invalid }
        return first == last ? .unique(first) : .ambiguous(first,last)
    }
}
